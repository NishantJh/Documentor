# GitHub development workflow

The source repository is https://github.com/NishantJh/Documentor. The connected GitHub integration can now create and read repository files directly, so code changes do not require manual archive uploads or pushes from the user.

For changes made through the integration, commits are currently created directly on the default branch. The next improvement should be a branch-and-pull-request workflow with CI validation before merge.

Do not commit live homelab inventory, IP maps if sensitive, screenshots, config exports, tokens, private keys, database files or generated evidence. Keep these in protected persistent storage with separate off-host backups.

CI runs the Python test suite on pushes and pull requests. Review Actions results before deploying to the Proxmox host.
