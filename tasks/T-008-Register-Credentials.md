# Task T-008: Register ELK Credentials

**Status**: ✅ Done
**Epic**: Security / DX
**Estimate**: 30 mins

## Description
Register the generated Elastic credentials in the TUI's Credential Manager so they can be retrieved via Option 4 ("View Credentials").

## Inputs
- **Name**: `elastic-admin`
- **Username**: `elastic`
- **Password**: *(Retrieved from verification step)*
- **Description**: `Elasticsearch Superuser`

## Execution
- Use `lib/credstore.sh` -> `credstore_add`.
