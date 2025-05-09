import { util } from "@aws-appsync/utils";
import {
  select,
  createPgStatement,
  toJsonObject,
  agg,
  typeHint,
} from "@aws-appsync/utils/rds";

const TABLE_NAME = "lims";
// Map each type to a list of field names
const FIELD_TYPE_MAP = {
  date: ["sequencing_run_date"],
  timestamp: ["load_datetime"],
  decimal: [],
};

// Helper: get field type from the map
function getFieldType(field) {
  for (const [type, fields] of Object.entries(FIELD_TYPE_MAP)) {
    if (fields.includes(field)) return type;
  }
  return null;
}

// Casting function based on type
function castValue(val, type) {
  if (type === "date") {
    
    return Array.isArray(val)
      ? val.map(function (v) {
          return typeHint.DATE(v);
        })
      : typeHint.DATE(val);
  }

  if (type === "timestamp") {
    return Array.isArray(val)
      ? val.map(function (v) {
          return typeHint.TIMESTAMP(v);
        })
      : typeHint.TIMESTAMP(val);
  }

  if (type === "decimal") {
    return Array.isArray(val)
      ? val.map(function (v) {
          return typeHint.DECIMAL(v);
        })
      : typeHint.DECIMAL(val);
  }
  return val;
}

// Cast a filter's field condition if needed
function castFieldCondition(field, condition) {
  const type = getFieldType(field);
  if (!type) return condition;

  const casted = {};
  for (const [op, val] of Object.entries(condition)) {
    casted[op] = castValue(val, type);
  }
  return casted;
}

// Apply casting to all fields in the filter
function castedFilter(filter) {
  const result = {};
  for (const [field, condition] of Object.entries(filter)) {
    result[field] = castFieldCondition(field, condition);
  }
  return result;
}
/**
 * @param {import('@aws-appsync/utils').Context} ctx the context
 * @returns {*} the request
 */
export function request(ctx) {
  const { filter = {}, limit = 100, orderBy: _o = [], offset = 0 } = ctx.args;
  const orderBy = _o
    .map((x) => Object.entries(x))
    .flat()
    .map(([column, dir]) => ({ column, dir }));

  const where = Array.isArray(filter.and)
    ? { and: filter.and.map(castedFilter) }
    : castedFilter(filter);

  const selectStatement = select({
    table: TABLE_NAME,
    columns: "*",
    limit,
    offset,
    where: where,
    orderBy,
  });

  const countStatement = select({
    table: TABLE_NAME,
    columns: [agg.count("*")],
    where: where,
  });

  return createPgStatement(selectStatement, countStatement);
}

/**
 * Returns the result or throws an error if the operation failed.
 * @param {import('@aws-appsync/utils').Context} ctx the context
 * @returns {*} the result
 */
export function response(ctx) {
  const {
    args: { limit = 100, nextToken },
    error,
    result,
  } = ctx;
  if (error) {
    return util.appendError(error.message, error.type, result);
  }
  const selectResult = toJsonObject(result)[0];
  const countResult = toJsonObject(result)[1][0].count;

  return {
    items: selectResult,
    totalCount: countResult,
  };
}
