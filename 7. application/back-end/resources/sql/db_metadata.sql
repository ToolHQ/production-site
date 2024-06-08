with constraint_vs_column as (
  select
    constraint_column_usage.table_catalog,
    constraint_column_usage.table_schema,
    constraint_column_usage.table_name,
    constraint_column_usage.constraint_catalog,
    constraint_column_usage.constraint_schema,
    constraint_column_usage.constraint_name,
    array_agg(constraint_column_usage.column_name) columns_names
  from information_schema.constraint_column_usage
  group by
    constraint_column_usage.table_catalog,
    constraint_column_usage.table_schema,
    constraint_column_usage.table_name,
    constraint_column_usage.constraint_catalog,
    constraint_column_usage.constraint_schema,
    constraint_column_usage.constraint_name
), table_grouped_constraints as (
  select
    table_constraints.table_catalog,
    table_constraints.table_schema,
    table_constraints.table_name,
    array_agg(json_build_object(
      'name', table_constraints.constraint_name,
      'type', table_constraints.constraint_type,
      'clause', check_constraints.check_clause,
      'columns', coalesce(constraint_vs_column.columns_names, '{}')
    )) table_constraints
  from information_schema.table_constraints
  left join information_schema.check_constraints on
    check_constraints.constraint_catalog = table_constraints.constraint_catalog and
    check_constraints.constraint_schema = table_constraints.constraint_schema and
    check_constraints.constraint_name = table_constraints.constraint_name
  left join constraint_vs_column on
    constraint_vs_column.constraint_catalog = table_constraints.constraint_catalog and
    constraint_vs_column.constraint_schema = table_constraints.constraint_schema and
    constraint_vs_column.constraint_name = table_constraints.constraint_name
  group by
    table_constraints.table_catalog,
    table_constraints.table_schema,
    table_constraints.table_name
), tables_with_columns as (
select
  tables.table_catalog "catalog",
  tables.table_schema "schema",
  tables.table_name "name",
  tables.table_type "type",
  array_agg(json_build_object(
	'position', columns.ordinal_position,
	'name', columns.column_name,
	'defaultValue', columns.column_default,
	'nullable', columns.is_nullable,
	'type', columns.udt_name,
	'dataType', columns.data_type,
	'maxChars', columns.character_maximum_length,
	'maxBytes', columns.character_octet_length,
	'numericPrecision', columns.numeric_precision,
	'numericRadix', columns.numeric_precision_radix,
	'numericScale', columns.numeric_scale,
	'dateTimePrecision', columns.datetime_precision,
	'collationCatalog', columns.collation_catalog,
	'collationSchema', columns.collation_schema,
	'collationName', columns.collation_name
  ) order by columns.ordinal_position) "columns"
from information_schema.tables
left join information_schema.columns on
  columns.table_catalog = tables.table_catalog and
  columns.table_schema = tables.table_schema and
  columns.table_name = tables.table_name
group by
  tables.table_catalog,
  tables.table_schema,
  tables.table_name,
  tables.table_type
order by
  tables.table_catalog,
  tables.table_schema,
  tables.table_name,
  tables.table_type
)
select
  tables_with_columns.*,
  coalesce(table_grouped_constraints.table_constraints, '{}') "constraints"
from tables_with_columns
left join table_grouped_constraints on
  table_grouped_constraints.table_catalog = tables_with_columns.catalog and
  table_grouped_constraints.table_schema = tables_with_columns.schema and
  table_grouped_constraints.table_name = tables_with_columns.name
