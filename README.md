# yavs-action

A GitHub Action that installs [yavs](https://github.com/ru551n/yavs), the VHDL simulator, from its
release archives. It verifies the archive against the release's `SHA256SUMS`, checks that the `yavs`
inside is the version asked for, and puts it on `PATH`. Nothing else needs to be installed.

```yaml
steps:
  - uses: actions/checkout@v5
  - uses: ru551n/yavs-action@v1
    with:
      version: 0.14.0
  - run: yavs analyze --work=work:build/work src/hello_tb.vhd
  - run: yavs run --work=work:build/work hello_tb
```

**Pin the version.** A pinned version gives the same simulator on every run, until you change it;
`latest` can change the results of your CI on the day a release comes out.

## Inputs

| Input | Default | What it is |
|---|---|---|
| `variant` | `default` | Which archive. `default` is built for x86-64-v3 and needs a CPU with AVX2, which GitHub-hosted runners have. `compat` is the archive for any x86_64 CPU, for self-hosted runners without AVX2; it needs yavs 0.14.0 or newer and fails for an older version. On Linux aarch64 there is one archive, so `compat` installs it and prints a notice. Any other value fails. |
| `version` | `latest` | An exact yavs version, such as `0.11.0` or `v0.11.0`, or `latest`: the newest stable release, meaning the highest release tagged `vX.Y.Z`. |

```yaml
  - uses: ru551n/yavs-action@v1
    with:
      version: 0.14.0
      variant: compat
```

## Outputs

| Output | What it is |
|---|---|
| `version` | The installed version, without a leading `v`. |
| `path` | The directory that holds `yavs`, already on `PATH`. |

## Runners

Linux x86_64, Linux aarch64 and Windows x86_64: the platforms yavs has archives for. The step uses
`bash`, `curl`, `sha256sum` and `tar` (`unzip` on Windows), which GitHub's runners have. A self-hosted
runner or a container without one of them gets an error naming it.

With [VUnit](https://github.com/VUnit/vunit), add `pip install vunit-yavs`: it finds `yavs` on `PATH`.

## When it fails

Every error says what went wrong and what to do about it: an unknown version, a runner without an
archive, a failed download, a checksum that does not match, a `yavs` that does not run or names
another version, an unknown `variant`, `compat` with a yavs older than 0.14.0. Nothing falls back to another version.

## Versions

This action has versions of its own, unrelated to the versions of yavs. `v1.0.0` is an exact release
of the action and `v1` follows the newest `v1.x.y`.

## Licence

MIT or Apache-2.0 at your option, as yavs: [LICENSE-MIT](LICENSE-MIT), [LICENSE-APACHE](LICENSE-APACHE).
