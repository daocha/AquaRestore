# Basic grading core

AquaRestore's tuned color grading (scene analysis, grading formula and GPU shaders) is kept in a
private repository, mounted at `core/` as a git submodule. This folder is a public stand-in with the
same API and a deliberately basic formula, so the app builds and runs without that access.

Without access to the private core, run once after cloning:

```sh
scripts/use-core-stub.sh
```

Results with this core are noticeably weaker than the released app.
