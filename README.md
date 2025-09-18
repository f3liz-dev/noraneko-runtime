# Welcome to Noraneko Runtime Repository

This is a repository for build Noraneko runtime from Firefox source.

## Contribution Guide

When I run pull-upstream action, the whole directory except

```js
[".git/**/*",".github/**/*",".gitmodules", "noraneko/**/*"]
```

will be overrided by Firefox source.

If you want to add some files, please use .github directory and also you could modify [.github/workflows/pull-upstream.yml](.github/workflows/pull-upstream.yml)

Thank you for reading. Have a nice day!

## Useful Links

[![Link to Noraneko Main Repository](.github/assets/readme/Link2MainRepo.svg)](https://github.com/nyanrus/noraneko/)

## LICENSE

[Mozilla Public License 2.0 (MPL2.0)](./.github/LICENSE) for noraneko sources.  
[LICENSE of Firefox sources](./LICENSE)
