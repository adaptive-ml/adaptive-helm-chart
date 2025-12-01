<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Upgrade Guide](#upgrade-guide)
  - [0.17.x to 0.18.0](#017x-to-0180)
    - [Breaking Change: Database Configuration Format](#breaking-change-database-configuration-format)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# Upgrade Guide

This document describes breaking changes between Helm chart versions and how to migrate your configuration.

## 0.17.x to 0.18.0

### Breaking Change: Database Configuration Format

The `secrets.dbUrl` field has been replaced with separate database configuration fields.

**Old format (0.17.x and earlier):**

```yaml
secrets:
  dbUrl: "postgresql://username:password@db_address:5432/db_name"
```

**New format (0.18.0+):**

```yaml
secrets:
  db:
    username: "username"
    password: "password"
    host: "db_address:5432"  # Host and port
    database: "db_name"
```
