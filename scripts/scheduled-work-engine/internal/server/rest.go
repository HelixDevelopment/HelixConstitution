// Package server builds the gin HTTP handler exposing the scheduled-work
// service over REST and MCP-over-HTTP. The same *gin.Engine is served over
// HTTP/1.1, HTTP/2 and HTTP/3 by cmd/scheduled-work.
package server

import (
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/HelixDevelopment/HelixConstitution/scripts/scheduled-work-engine/internal/store"
)

// API wires a store to gin routes.
type API struct {
	Store *store.Store
}

// NewEngine returns a configured *gin.Engine (implements http.Handler, so
// it is served identically over h1/h2/h3). brotliQuality < 0 disables the
// brotli middleware.
func NewEngine(a *API, brotliQuality int) *gin.Engine {
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Recovery())
	// Bound every request body before any handler reads it (hardening for a
	// non-loopback bind). Applies to REST + MCP routes alike.
	r.Use(MaxBody(maxBodyBytes()))
	if brotliQuality >= 0 {
		r.Use(Brotli(brotliQuality))
	}

	// /healthz stays open (liveness probe) even when auth is enabled.
	r.GET("/healthz", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok", "items": a.Store.Count()})
	})

	// Optional bearer-token auth: enabled iff SWQ_AUTH_TOKEN is set. When
	// unset, behaviour is unchanged (frictionless loopback default).
	var authMW []gin.HandlerFunc
	if tok := authToken(); tok != "" {
		authMW = []gin.HandlerFunc{BearerAuth(tok)}
	}

	v1 := r.Group("/api/v1", authMW...)
	{
		v1.POST("/items", a.createItem)
		v1.GET("/items", a.listItems)
		v1.GET("/items/overdue", a.overdue)
		v1.GET("/items/needs-verification", a.needsVerification)
		v1.GET("/items/:id", a.getItem)
		v1.PATCH("/items/:id/status", a.updateStatus)
		v1.POST("/items/:id/done", a.markDone)
		v1.DELETE("/items/:id", a.deleteItem)
	}

	// MCP-over-HTTP (JSON-RPC 2.0). See internal/mcp. Protected by the same
	// optional bearer-token auth as the REST surface.
	mcpChain := append(append([]gin.HandlerFunc{}, authMW...), a.mcpHTTP)
	r.POST("/mcp", mcpChain...)

	return r
}

// bindJSON binds the JSON request body, translating an oversized body
// (*http.MaxBytesError from the MaxBody middleware) into a clean 413 and any
// other malformed body into a 400. It returns false (and has already written
// a response) when binding failed — the caller MUST return.
func bindJSON(c *gin.Context, obj any) bool {
	if err := c.ShouldBindJSON(obj); err != nil {
		var mbe *http.MaxBytesError
		if errors.As(err, &mbe) {
			c.JSON(http.StatusRequestEntityTooLarge, gin.H{"error": "request body too large"})
		} else {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		}
		return false
	}
	return true
}

type createReq struct {
	Title       string     `json:"title"`
	Description string     `json:"description"`
	Status      string     `json:"status"`
	DueAt       *time.Time `json:"due_at"`
	Tags        []string   `json:"tags"`
	Source      string     `json:"source"`
	Notes       string     `json:"notes"`
}

func (a *API) createItem(c *gin.Context) {
	var req createReq
	if !bindJSON(c, &req) {
		return
	}
	it, err := a.Store.Create(store.CreateParams{
		Title:       req.Title,
		Description: req.Description,
		Status:      store.Status(req.Status),
		DueAt:       req.DueAt,
		Tags:        req.Tags,
		Source:      req.Source,
		Notes:       req.Notes,
	})
	if err != nil {
		writeStoreErr(c, err)
		return
	}
	c.JSON(http.StatusCreated, it)
}

func (a *API) listItems(c *gin.Context) {
	items := a.Store.List(store.Status(c.Query("status")))
	c.JSON(http.StatusOK, gin.H{"items": items, "count": len(items)})
}

func (a *API) getItem(c *gin.Context) {
	it, err := a.Store.Get(c.Param("id"))
	if err != nil {
		writeStoreErr(c, err)
		return
	}
	c.JSON(http.StatusOK, it)
}

type statusReq struct {
	Status string `json:"status"`
	Notes  string `json:"notes"`
}

func (a *API) updateStatus(c *gin.Context) {
	var req statusReq
	if !bindJSON(c, &req) {
		return
	}
	it, err := a.Store.UpdateStatus(c.Param("id"), store.Status(req.Status), req.Notes)
	if err != nil {
		writeStoreErr(c, err)
		return
	}
	c.JSON(http.StatusOK, it)
}

func (a *API) markDone(c *gin.Context) {
	var req statusReq
	// Notes are optional (a missing / empty body is tolerated), but an
	// oversized body still hits the MaxBody cap and MUST be rejected cleanly.
	if err := c.ShouldBindJSON(&req); err != nil {
		var mbe *http.MaxBytesError
		if errors.As(err, &mbe) {
			c.JSON(http.StatusRequestEntityTooLarge, gin.H{"error": "request body too large"})
			return
		}
		// any other error (empty/malformed small body) is tolerated: notes optional
	}
	it, err := a.Store.MarkDone(c.Param("id"), req.Notes)
	if err != nil {
		writeStoreErr(c, err)
		return
	}
	c.JSON(http.StatusOK, it)
}

func (a *API) deleteItem(c *gin.Context) {
	if err := a.Store.Delete(c.Param("id")); err != nil {
		writeStoreErr(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func (a *API) overdue(c *gin.Context) {
	items := a.Store.Overdue()
	c.JSON(http.StatusOK, gin.H{"items": items, "count": len(items)})
}

func (a *API) needsVerification(c *gin.Context) {
	items := a.Store.NeedsVerification()
	c.JSON(http.StatusOK, gin.H{"items": items, "count": len(items)})
}

func writeStoreErr(c *gin.Context, err error) {
	switch {
	case errors.Is(err, store.ErrNotFound):
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
	case errors.Is(err, store.ErrInvalidStatus), errors.Is(err, store.ErrEmptyTitle):
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
	default:
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
	}
}
