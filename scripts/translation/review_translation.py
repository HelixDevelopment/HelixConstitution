#!/usr/bin/env python3
"""Independent per-language translation reviewer (HelixConstitution §translation-review).

Compares an English SOURCE against a TRANSLATION using an INDEPENDENT reviewer
model (a different provider/model than the one that produced the translation),
and emits a strict JSON verdict with hard evidence. No bluff: a real API call
is made; a missing/failed call yields verdict=ERROR (never a fake PASS).

Usage:
  review_translation.py --src EN.md --translated FILE.md --lang <code> [--article] \
      [--provider groq|openrouter|mistral|zhipu] [--out path.json]

Exit: 0=PASS, 1=FAIL, 2=ERROR.
"""
import argparse, json, os, re, sys, time, urllib.request, urllib.error

LANG_NAMES = {
    "en": "English", "ru": "Russian", "sr": "Serbian", "de": "German",
    "es": "Spanish", "fr": "French", "be": "Belarusian", "zh": "Chinese (Simplified)",
    "kk": "Kazakh", "hi": "Hindi", "ja": "Japanese", "ko": "Korean",
    "ar": "Arabic", "fa": "Persian", "tr": "Turkish", "uz": "Uzbek", "az": "Azerbaijani",
}
# provider -> (endpoint, api-key env var, default model)
PROVIDERS = {
    "groq":       ("https://api.groq.com/openai/v1/chat/completions", "GROQ_API_KEY", "llama-3.3-70b-versatile"),
    "openrouter": ("https://openrouter.ai/api/v1/chat/completions", "OPENROUTER_API_KEY", "meta-llama/llama-3.3-70b-instruct"),
    "mistral":    ("https://api.mistral.ai/v1/chat/completions", "MISTRAL_API_KEY", "mistral-large-latest"),
    "zhipu":      ("https://open.bigmodel.cn/api/paas/v4/chat/completions", "ZHIPU_API_KEY", "glm-4-flash"),
    "cohere":     ("https://api.cohere.com/v2/chat", "COHERE_API_KEY", "command-r-plus-08-2024"),
}


def strip_frontmatter(t):
    if t.startswith("---"):
        lines = t.split("\n")
        fences = [i for i, l in enumerate(lines) if l.strip() == "---"]
        if len(fences) >= 2:
            return "\n".join(lines[fences[1] + 1:]).strip()
    return t


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--translated", required=True)
    ap.add_argument("--lang", required=True)
    ap.add_argument("--article", action="store_true")
    ap.add_argument("--provider", default=os.environ.get("REVIEW_PROVIDER", "groq"))
    ap.add_argument("--model", default=os.environ.get("REVIEW_MODEL", ""))
    ap.add_argument("--out", default="")
    a = ap.parse_args()

    src = open(a.src, encoding="utf-8").read()
    tr = open(a.translated, encoding="utf-8").read()
    if a.article:
        src, tr = strip_frontmatter(src), strip_frontmatter(tr)
    langname = LANG_NAMES.get(a.lang, a.lang)
    if a.provider not in PROVIDERS:
        print(json.dumps({"verdict": "ERROR", "error": "unknown provider " + a.provider})); sys.exit(2)
    url, keyenv, default_model = PROVIDERS[a.provider]
    model = a.model or default_model
    key = os.environ.get(keyenv, "")
    if not key:
        print(json.dumps({"verdict": "ERROR", "error": "missing " + keyenv})); sys.exit(2)

    system = (
        "You are a professional NATIVE %s linguistic reviewer, fully INDEPENDENT from whoever produced the translation. "
        "Rigorously compare the English SOURCE and the %s TRANSLATION and judge: accuracy/fidelity, fluency/naturalness, "
        "completeness (nothing omitted or invented), correct script & orthography for %s, and that NO English text was left "
        "untranslated (proper nouns, brand names, code, and URLs may legitimately remain). "
        "Respond with STRICT MINIFIED JSON only and nothing else: "
        '{"verdict":"PASS|FAIL","accuracy":1-5,"fluency":1-5,"completeness":1-5,"script_ok":true|false,'
        '"untranslated_leftovers":true|false,"issues":["short issue"]}. '
        "verdict=PASS only if accuracy>=4 AND fluency>=4 AND completeness>=4 AND script_ok AND not untranslated_leftovers."
    ) % (langname, langname, langname)
    user = "SOURCE (English):\n%s\n\n---\nTRANSLATION (%s):\n%s" % (src[:12000], langname, tr[:12000])

    payload = json.dumps({
        "model": model, "temperature": 0,
        "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
    }).encode("utf-8")
    req = urllib.request.Request(url, data=payload, headers={
        "Authorization": "Bearer " + key,
        "Content-Type": "application/json",
        "User-Agent": "Mozilla/5.0 (HelixConstitution translation-reviewer)",
        "Accept": "application/json",
    })
    resp, last_err = None, ""
    for attempt in range(4):
        try:
            resp = json.load(urllib.request.urlopen(req, timeout=120)); break
        except urllib.error.HTTPError as e:
            last_err = "HTTP %s: %s" % (e.code, e.read()[:160].decode("utf-8", "ignore"))
            if e.code in (429, 500, 502, 503, 529):
                time.sleep(8 * (attempt + 1)); continue
            break
        except Exception as e:
            last_err = str(e)[:160]; time.sleep(5 * (attempt + 1)); continue
    if resp is None:
        print(json.dumps({"verdict": "ERROR", "error": last_err})); sys.exit(2)

    if a.provider == "cohere":
        content = resp["message"]["content"][0]["text"].strip()
    else:
        content = resp["choices"][0]["message"]["content"].strip()
    m = re.search(r"\{.*\}", content, re.S)
    data = json.loads(m.group(0)) if m else {"verdict": "ERROR", "raw": content[:300]}
    data.update({"_lang": a.lang, "_provider": a.provider, "_model": model, "_translated": a.translated})
    out = json.dumps(data, ensure_ascii=False)
    if a.out:
        os.makedirs(os.path.dirname(a.out), exist_ok=True)
        open(a.out, "w", encoding="utf-8").write(out)
    print(out)
    sys.exit(0 if data.get("verdict") == "PASS" else (1 if data.get("verdict") == "FAIL" else 2))


if __name__ == "__main__":
    main()
