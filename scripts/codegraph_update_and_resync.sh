(pull_all || true) && ((codegraph init || true) && ((codegraph sync && codegraph index) || true)) && ((commit || true) && (push_all || true))
