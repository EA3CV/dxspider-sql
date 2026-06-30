# DXSpider-SQL

DXSpider-SQL is a fork of the original **DXSpider** cluster software by **Dirk Koopman G1TLH**.

The purpose of this project is to provide a fully integrated SQL backend while preserving compatibility with the original DXSpider architecture and operation.

## Original Project

**DXSpider**

Author: Dirk Koopman G1TLH

Upstream repository:

git://scm.dxspider.org/spider

## This Fork

**DXSpider-SQL**

Maintainer: Kin EA3CV

Repository:

https://github.com/EA3CV/dxspider-sql

## Main Features

- Native SQL backend support.
- MariaDB/MySQL support.
- SQLite support.
- Automatic database and table creation.
- SQL replacement for the original DBM storage where implemented.
- SQL management commands.
- SQL import/export utilities.
- Automatic SQL schema verification.
- Improved Docker deployment support.
- SQL backend maintenance and enhancements.
- Additional bug fixes and performance improvements.

## Compatibility

DXSpider-SQL has been designed to remain as compatible as possible with the original DXSpider project.

Existing DXSpider concepts, commands and behaviour have been preserved wherever practical while replacing legacy storage mechanisms with SQL implementations.

## License

This project is distributed under the Artistic License 2.0.

Original DXSpider:

Copyright (c) Dirk Koopman G1TLH

Additional SQL backend, enhancements and maintenance:

Copyright (c) 2024-2026 Kin EA3CV

## Acknowledgements

This project would not exist without the original DXSpider software developed and maintained by Dirk Koopman G1TLH.

DXSpider remains the upstream project from which this SQL fork originated.
