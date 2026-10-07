# Tools and Results Contract

## Installed Tools
- `torah_ocr_excerpt`: Transcribes text from attachment handle and normalized crop region.
- `torah_identify_excerpt`: Deterministic candidate matcher across enabled corpora.
- `torah_search_text`: Lexical anchor and phrase search.
- `torah_get_section`: Retrieves canonical passage text and context.
- `torah_get_links`: Retrieves commentaries (Rashi, Tosafot) and cross-references.
- `torah_get_topics`: Retrieves conceptual tags.
- `torah_open_source`: Navigates to source in Hanlin or Maktabah.

## Results Contract
- `status`: Must be one of `verified`, `ambiguous`, `notFound`, `insufficientImage`, `corpusUnavailable`.
- `sourceRole`: Must distinguish `primaryWork` from `citedWork` and `liturgicalCommon`.
