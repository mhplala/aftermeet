# Synthetic Knowledge Fixtures

These fixtures exist only to test the knowledge pipeline. They must never contain copied meeting text, real people, real product names, internal URLs, email addresses, access tokens, or paths under a user's home directory.

## Rules

1. Use fictional projects and speakers such as `松果计划` and `甲/乙/丙`.
2. Keep every expected fact explicit in the transcript; missing owners and dates must remain absent.
3. Include adversarial pairs where only a number, date, or negation changes.
4. Mark personnel-review fixtures as `restricted` even though all content is fictional.
5. Generate very long transcripts inside tests from a short fictional paragraph instead of committing large text blobs.
6. Expectations describe extraction invariants, not model prose.
7. Real golden questions and answers belong under Application Support and are never committed.
