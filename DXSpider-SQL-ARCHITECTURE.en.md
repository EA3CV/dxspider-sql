# DXSpider-SQL Architecture Notes

## Objective

DXSpider-SQL is a DXSpider fork that aims to remain as compatible as
possible with the official project while providing a complete SQL
backend (MariaDB and SQLite).

## Principles

1.  Compatibility first.
2.  Do not modify the DXSpider protocol except for verified bug fixes.
3.  `perl/Version.pm` is the authoritative source for program name,
    version and build.
4.  Maintain equivalent behaviour for MariaDB and SQLite.
5.  When conflicts with upstream SQL tables exist, DXSpider-SQL may use
    its own names (e.g. `badips` → `badip`). The legacy table is never
    deleted automatically.
6.  Historical `badip.*` files are never renamed.
7.  Permanent modules belong in `perl/`; `local/` is for node-specific
    configuration only.
8.  The master source tree is `dx-sql-next`; Docker trees are deployment
    copies.
9.  Every divergence from upstream must have a documented technical
    reason.
