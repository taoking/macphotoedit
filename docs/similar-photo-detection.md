# Similar Photo Detection

## Scope

Phase 15 adds a local perceptual-similarity review tool. It is separate from
the existing exact-duplicate SHA-256 scan:

- Exact duplicate detection proves equal source bytes only after same-size
  candidate grouping.
- Similar photo detection decodes every currently available Catalog photo with
  ImageIO and computes a 64-bit dHash from a 9×8 luminance sample.

dHash preserves left-to-right brightness relationships, so it is useful for
resized copies, JPEG re-exports/recompression and uniform, small exposure or
colour shifts. It is not semantic search, face recognition, proof of identity
or a deletion recommendation.

## Local-only data flow

```text
User starts “查找相似照片”
→ security-scoped read of referenced original
→ ImageIO thumbnail (maximum 96 px)
→ 9×8 local raster → 64-bit dHash
→ Catalog cache + local Hamming grouping
→ Similar Group / similarity score review UI
```

No source file is copied, edited, moved, deleted or uploaded. The Catalog
stores only a 16-character dHash digest, its algorithm name, source file size,
source modification time and computation timestamp. A changed file size or
modification time invalidates the cached digest automatically. If ImageIO or
rasterization fails, that asset is reported as not analysed and never receives
a fabricated fallback hash.

## Grouping and score

The current review threshold is Hamming distance `≤ 8` out of 64 dHash bits.
The UI score is `(64 - distance) / 64 × 100`, rounded to an integer. It is a
pixel-structure proximity score, not a probability that two photos are the
same scene.

A BK-tree indexes Hamming distance. It evaluates nearby visual hashes without
an all-pairs scan; duplicate digest nodes use one representative edge to keep
large duplicate/burst clusters from expanding quadratically. Similar groups are
connected components, so a member may be connected transitively. The UI shows
the comparison edges that formed the group, rather than pretending every member
has been directly compared with every other member.

## Deliberate boundaries

- No automatic deletion, source move, trash action or rating change is
  attached to similarity results. Existing source deletion still requires the
  separate explicit Move to Trash flow.
- No cloud API, Vision feature print, face grouping or semantic search is used.
- dHash can miss heavy crops, rotation, major retouching or non-uniform edits;
  it can also produce false positives for simple repetitive graphics. Users
  must inspect displayed photos before taking any action.
- The first scan necessarily reads available photo originals. Later scans reuse
  hashes whose file size and modification time still match; actual 10k–100k
  library timing remains a manual performance check.
