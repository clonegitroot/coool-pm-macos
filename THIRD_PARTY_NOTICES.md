# Third-party notices

The Coool PM license covers original Coool PM material. These components
retain their upstream licenses.

| Component | License information |
| --- | --- |
| SQLCipher | [BSD-style license and notices](Resources/SQLCipher-LICENSE.md), copied into built app bundles. |
| Sparkle | [Upstream distribution and license](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.1). Optional updater builds include the upstream notice. |
| Optional local AI helper dependencies | [Pinned Swift package dependencies](LocalAI/Package.resolved) identify MLX Swift, MLX Swift LM, Swift ASN.1, Swift Collections, Swift Crypto, Swift Jinja, Swift Numerics, Swift Transformers and yyjson. The build copies upstream notices into the app's `LocalAI-Licenses` resources. |
| Optional Qwen3 models | Model weights are downloaded separately. See the publisher's model cards and terms for [1.7B](https://huggingface.co/mlx-community/Qwen3-1.7B-4bit), [4B](https://huggingface.co/mlx-community/Qwen3-4B-4bit) and [8B](https://huggingface.co/mlx-community/Qwen3-8B-4bit). |
