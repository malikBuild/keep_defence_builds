# Web builds template

Template for **public GitHub Pages repos that host a game's web builds**.
The game's code can stay private: its CI pushes only the exported web build
here. Free GitHub plan, no build step, no dependencies.

- **Engine-agnostic:** any folder with an `index.html` works (e.g. a Godot
  web export).
- **No history:** every publish replaces `main` with **one commit**, so the
  repo never grows.
- **Newest builds kept:** the 6 newest by default (`MAX_BUILDS`). Each build
  lives in `builds/<slot>/`, e.g. `v0.2`, `pr-12`.
- **Safe in parallel:** each publish starts from the current `main` and
  pushes with a lease; if another build landed meanwhile it retries, so no
  build is lost.
- **Phone-first landing page:** a big PLAY button for the newest build, the
  older builds, and an optional how-to.
  Black and white (follows the phone's dark/light setting) with one accent
  colour, turquoise by default.

## Make a builds repo from this template
1. On GitHub: **Use this template** → *Create a new repository*. Make it
   **public** and name it `<game>_builds`.
2. Edit **`site.json`**: title, tagline, accent colour, icon (a URL or a file
   you add next to it, e.g. `icon.svg`) and `orientation` (`portrait`,
   `landscape` or `any`).
   - Edit **`howto.html`** (plain HTML, shown under PLAY), or delete it.
     CI never touches either file.
3. Settings → Pages → *Deploy from a branch* → `main` / root.
4. Make a deploy key on your computer: `ssh-keygen -t ed25519 -N "" -f deploy`
   - Here: Settings → Deploy keys → Add. Paste `deploy.pub`, tick
     **Allow write access**.
   - In the **game** repo: Settings → Secrets → Actions. Add the contents of
     `deploy` as a secret, e.g. `BUILDS_DEPLOY_KEY`.
   - Then delete both key files.

## Publish from the game's CI
```yaml
- name: Publish web build
  env:
    DEPLOY_KEY: ${{ secrets.BUILDS_DEPLOY_KEY }}
  run: |
    key=$RUNNER_TEMP/builds_key
    printf '%s\n' "$DEPLOY_KEY" > "$key"; chmod 600 "$key"
    export GIT_SSH_COMMAND="ssh -i $key -o StrictHostKeyChecking=accept-new"
    git clone -q --depth 1 git@github.com:OWNER/GAME_builds.git builds-site
    builds-site/publish.sh build/web "$SLOT" "My Game $SLOT" \
      "$GITHUB_REF_NAME" "$GITHUB_SHA"
```
- `publish.sh <web_dir> <slot> "<title>" [source] [sha]` adds or replaces a
  build. Slots use letters, digits, `.`, `_`, `-`.
- `publish.sh --remove <slot>` drops one (e.g. when a PR closes). Removing a
  slot that isn't there is a no-op.
- A build is live at `https://OWNER.github.io/GAME_builds/builds/<slot>/`;
  the landing page is the repo root.

## Files
| File | Who edits it |
|---|---|
| `site.json`, `howto.html` (+ icon) | You, once per game. Never overwritten. |
| `index.html`, `publish.sh`, `README.md` | The template |
| `builds/`, `builds.json` | CI only, rewritten on every publish |

**Template updates:** copy the three template files in and amend the single
commit (it has no parent, so `main` stays one commit):
```sh
git clone -q --depth 1 git@github.com:OWNER/GAME_builds.git && cd GAME_builds
cp ../web-builds-template/{index.html,publish.sh,README.md} .
git commit -qa --amend -m "Update from web-builds-template"
git push --force-with-lease origin main
```

Godot web exports with `variant/thread_support=false` need no special
headers, so they run on Pages as is.
