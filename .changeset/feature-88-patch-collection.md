---
"deja-groove": minor
---

Add PATCH /v1/collection/{id} endpoint to update a collection record's format and notes fields. Introduces the `RecordFormat` value type (vinyl/cd/cassette/other), `UpdateCollectionUseCase`, and V017 migration adding a CHECK constraint on the `format` column. iOS `ApiClient` updated with `patchCollection()` using field-omitting encoding.
