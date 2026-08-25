---
name: check-app
description: Use this skill to check app prerelease status.
disable-model-invocation: true
---

# Check AL prerelease apps

Use this procedure for `/check-app "C:\...\.output\file.app" [more full local paths...]`
and `/check-apps ...`.

## Scope

Each input must be a fully qualified local `.app` path directly inside the `.output`
directory of an AL workspace. The workspace may be the Git checkout root or any directory
inside that checkout. The helper derives the checkout by resolving the enclosing Git
worktree from the workspace. All supported inputs in one run must derive the same checkout.
Reject UNC inputs and `.output` directories outside a Git worktree.

The helper derives the project-specific path from the checkout's Azure DevOps `origin` URL.
For example, `https://dev.azure.com/org/project/_git/repo` maps to
`\\filestorage\Projects\DevOps\org\project\repo`. Unsupported or unsafe origin URLs fail
rather than guessing a destination. The six destinations use the supplied package's leaf
filename:

- `\\filestorage\Projects\DevOps\!Prereleases\Latest-BC26|27|28`
- `\\filestorage\Projects\DevOps\<organization>\<project>\<repository>\Latest-BC26|27|28`

## Run

1. Preserve every supplied path, including spaces.
2. Locate `scripts/check-app.ps1` relative to this file and run it once, passing all paths
   to `-AppPath` as a PowerShell string array.
3. Report its package-level failures and final PASS or FAIL. Do not downgrade FAIL.

Always include an explicit summary in your response so the user never has to ask twice:

- A branches table for `WIP` and every discovered local `code/bcNN` branch with:
  branch name, tracked branch, short commit, tracking status, and `WIP merged` yes/no.
- A prerelease-destinations table for BC26/27/28 `!Prereleases` and project-specific
  folders with:
  destination path, expected branch mapping, package found yes/no, metadata/provenance result.
  Render each destination path as an explicit Markdown link in `[full path](full path)`
  form, using the complete path as both the visible label and link target. Do not wrap the
  path in inline code or shorten the visible label to its leaf directory.
- A final verdict line: `PASS` or `FAIL`.

The helper continues after individual failures. It uses only
`al GetPackageManifest <package-path>` for package metadata and normalizes manifest GUID
and commit formatting. Last-write times are evidence only; they never affect the result.

## Rules

- The checkout must currently be on `WIP` and be clean, including untracked files.
- App definitions come from every committed `app.json` in the local `WIP` Git tree, never
  from working-tree files. Manifest app ID selects the definition; duplicate IDs, invalid
  definitions, unresolved IDs, and version mismatches fail.
- Discover all local branches named exactly `code/bcNN`, where `NN` is numeric. At least
  one must exist, and `WIP` must be an ancestor of every one. Do not compare code branches
  against each other for pass/fail because BC-specific branches can legitimately diverge.
- Local `WIP` and every discovered code branch must equal their existing local
  `origin/<branch>` refs. Missing or divergent refs fail. The helper does not fetch.
- For destination BC `N`, select the local code branch with the highest `NN <= N`.
  A destination fails if no compatible branch exists.
- The supplied local package needs matching ID/version metadata; its `source.commit` is
  optional and ignored.
- Each of the six prerelease packages must exist, have matching ID/version metadata, and
  have a valid `source.commit` exactly equal to its selected local code-branch head.

The report shows Git status, committed WIP definitions, destination-to-branch mappings,
normalized ID/version/source metadata for each package, informational timestamps, and a
final result. Any failed check produces a nonzero exit.
