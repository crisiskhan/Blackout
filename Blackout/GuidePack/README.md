# GuidePack

Bundled field articles for the Field tab ask-engine.

- `articles.jsonl` — real wilderness copy, not lorem
- `inverted.json` — term → article id term-frequency
- No network. No edible plant verdicts. First aid is not medical advice.

Verify in the built app:

```bash
test -f "$APP/GuidePack/manifest.json" && wc -l "$APP/GuidePack/articles.jsonl"
```
