# Arquitectura de DXSpider-SQL

## Objetivo

DXSpider-SQL es un fork de DXSpider cuyo objetivo es mantener la máxima
compatibilidad posible con la versión oficial, incorporando un backend
SQL completo (MariaDB y SQLite).

## Principios

1.  Compatibilidad primero.
2.  No modificar el protocolo DXSpider salvo correcciones verificadas.
3.  `perl/Version.pm` es la fuente oficial de nombre, versión y build.
4.  Soporte equivalente para MariaDB y SQLite.
5.  Cuando exista conflicto de tablas con el proyecto oficial se podrán
    usar nombres propios (ej.: `badips` → `badip`). La tabla antigua
    nunca se elimina automáticamente.
6.  Los ficheros históricos `badip.*` nunca se renombran.
7.  Los módulos permanentes pertenecen a `perl/`; `local/` solo contiene
    configuración del nodo.
8.  El árbol maestro es `dx-sql-next`; los árboles Docker son copias de
    despliegue.
9.  Toda diferencia respecto a DXSpider oficial debe tener una
    justificación técnica documentada.
