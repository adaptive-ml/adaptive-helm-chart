# Upgrade Guide

This document describes breaking changes between Helm chart versions and how to migrate your configuration.

## 0.16.x to 0.17.0

### Breaking Change: Database Configuration Format

The `secrets.dbUrl` field has been replaced with separate database configuration fields.

**Old format (0.16.x and earlier):**

```yaml
secrets:
  dbUrl: "postgresql://username:password@db_address:5432/db_name"
```

**New format (0.17.0+):**

```yaml
secrets:
  db:
    username: "username"
    password: "password"
    host: "db_address:5432"  # Host and port
    database: "db_name"
```
