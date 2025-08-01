import { postgraphile } from "postgraphile";
import { PostGraphileAmberPreset } from "postgraphile/presets/amber";
import { makePgService } from "postgraphile/adaptors/pg";
import { grafserv } from "postgraphile/grafserv/fastify/v4";
import { makeV4Preset } from "postgraphile/presets/v4";
import fastify from "fastify";
import { PostGraphileConnectionFilterPreset } from "postgraphile-plugin-connection-filter";

export function constructDatabaseConnectionString(props: {
  host: string;
  port: string;
  database: string;
  username: string;
  password: string;
}): string {
  const { host, port, database, username, password } = props;
  return `postgres://${username}:${password}@${host}:${port}/${database}`;
}

export async function createApp({
  databaseConnectionString,
}: {
  databaseConnectionString: string;
}) {
  // Our PostGraphile configuration, we're going (mostly) with the defaults:
  /** @type {GraphileConfig.Preset} */
  const preset = {
    extends: [
      PostGraphileAmberPreset,
      PostGraphileConnectionFilterPreset,
      makeV4Preset({
        subscriptions: false,
        dynamicJson: true,
        setofFunctionsContainNulls: false,
        ignoreRBAC: true,
        disableDefaultMutations: true,
        simpleCollections: "omit",
        graphileBuildOptions: {
          // https://github.com/graphile-contrib/postgraphile-plugin-connection-filter#plugin-options
          connectionFilterAllowedOperators: [
            "isNull",
            "equalTo",
            "notEqualTo",
            "greaterThan",
            "lessThan",
            "greaterThanOrEqualTo",
            "lessThanOrEqualTo",
          ],
          connectionFilterArrays: false,
          connectionFilterComputedColumns: false,
          connectionFilterLogicalOperators: true,
          connectionFilterAllowNullInput: false,
          connectionFilterAllowEmptyObjectInput: false,
        },
      }),
    ],
    pgServices: [
      makePgService({
        connectionString: databaseConnectionString,
        schemas: [process.env.SCHEMA_NAME || "public"],
      }),
    ],
    grafast: {
      explain: false,
    },
    grafserv: {
      graphqlPath: "/graphql",
      graphiqlPath: "/graphiql",
      // Disable GraphQL over GET requests
      // This query params is also removed in the handler.ts
      graphqlOverGET: false,
      graphiql: true,
      // Recommended to set maxRequestLength to prevent DoS attacks (postgraphile docs)
      // Setting 10 000 bytes payload to start with
      maxRequestLength: 10000,
    },
    disablePlugins: ["NodePlugin"],
  };

  const pgl = postgraphile(preset);
  const serv = pgl.createServ(grafserv);
  const app = fastify();
  await serv.addTo(app);
  return app;
}
