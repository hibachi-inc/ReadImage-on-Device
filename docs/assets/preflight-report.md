# Image Preflight Report

Processed images: 2
Original total: 3.1 MB
Recommended delivery total: 140.3 KB
Estimated reduction: 95.6%

Applied fixes:
- Renamed assets to context-aware lower-kebab-case filenames.
- Converted delivery assets to WebP.
- Generated JPEG/PNG fallbacks.
- Prepared SEO/accessibility alt text suggestions.
- Stripped unnecessary metadata by re-encoding outputs.

## readimage-local-processing-flow

- Original: `generated-flow.png` (1672×941, 1.5 MB)
- Recommended delivery: `images/readimage-local-processing-flow-1200w.webp` (62.3 KB, 95.9% reduction)
- Mode: `seo`
- Role: `diagram`
- Alt: `画像をReadImageで端末内処理し、抽出テキスト・JSON・対応環境での日本語説明を出力する流れ`
- Variants:
  - `images/readimage-local-processing-flow-1200w.webp` — 1200×675, webp, 62.3 KB
  - `images/readimage-local-processing-flow-1200w.jpg` — 1200×675, jpg, 112.2 KB
- Decisions:
  - Generated responsive WebP variants plus fallback images.
  - Prepared HTML implementation guidance.
  - Non-hero SEO images can usually use lazy loading.
- Assumptions:
  - GitHub READMEの説明図。説明文の生成は対応環境に限られる。
  - SEO mode assumes the image will be used on a website or web page.
- Warnings:
  - 画像は端末内処理までを示す。出力を外部LLMへ渡す場合はテキストが外部送信される。
  - Check small responsive variants for text/readability before publishing.

## readimage-on-device-hero

- Original: `generated-hero.png` (1672×941, 1.6 MB)
- Recommended delivery: `images/readimage-on-device-hero-1200w.webp` (78.0 KB, 95.3% reduction)
- Mode: `seo`
- Role: `hero`
- Alt: `ReadImage on Device — 画像を端末内で読み取り、テキストとJSONへ変換するSwiftパッケージ`
- Variants:
  - `images/readimage-on-device-hero-1200w.webp` — 1200×675, webp, 78.0 KB
  - `images/readimage-on-device-hero-1200w.jpg` — 1200×675, jpg, 127.8 KB
- Decisions:
  - Generated responsive WebP variants plus fallback images.
  - Prepared HTML implementation guidance.
  - Treated as a likely first-view/LCP image; lazy loading is not recommended.
- Assumptions:
  - GitHub READMEの冒頭画像。サムネイルにも再利用できる概念図。
  - 1200px幅の単一配信画像を選択。GitHub専用の寸法要件としては扱わない。
  - SEO mode assumes the image will be used on a website or web page.
- Warnings:
  - 生成された画面とJSONカードは概念図で、実際の出力画面ではない。
  - 文字の可読性は縮小後も目視確認する。

## READMEへの適用

- AI Image DirectorのSEOモードで処理。
- 原本PNGは別フォルダに保持し、上書きしていません。
- 2枚のWebP配信容量：143,686 bytes（約140KB）。原本合計：3,264,323 bytes（約3.11MiB）。削減率95.6%。
- READMEではWebPのみを読み込み、JPEGは代替用途に同梱。
- 1200px幅の単一画像を採用。GitHub専用の推奨寸法とはしていません。
- 画面とJSONカードは概念図です。日本語説明は対応環境で利用できます。
