import { postgraphile } from "postgraphile";
import { PostGraphileAmberPreset } from "postgraphile/presets/amber";
import { makePgService } from "postgraphile/adaptors/pg";
import { grafserv } from "postgraphile/grafserv/fastify/v4";
import { makeV4Preset } from "postgraphile/presets/v4";
import fastify from "fastify";
import awsLambdaFastify from "@fastify/aws-lambda";
import { PostGraphileConnectionFilterPreset } from "postgraphile-plugin-connection-filter";

function constructDatabaseConnectionString(props: {
  host: string;
  port: string;
  database: string;
  username: string;
  password: string;
}): string {
  const { host, port, database, username, password } = props;
  return `postgres://${username}:${password}@${host}:${port}/${database}`;
}

async function getSecretManagerValue() {
  const secretARN = process.env.SECRET_ARN;
  if (!secretARN) {
    throw new Error("SECRET_ARN environment variable is not set");
  }

  const response = await fetch(
    `http://localhost:2773/secretsmanager/get?secretId=${secretARN}`,
    {
      headers: {
        "X-Aws-Parameters-Secrets-Token": process.env.AWS_SESSION_TOKEN!,
      },
    },
  );
  console.log("the response is", response);
  const bodyText = await response.text();
  console.log("the body text is", bodyText);
  return JSON.parse(bodyText).SecretString;
}

async function createApp({
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
        ignoreRBAC: false,
        disableDefaultMutations: true,
        simpleCollections: "only",
      }),
    ],
    pgServices: [
      makePgService({
        connectionString: databaseConnectionString,
        schemas: ["public"],
      }),
    ],
    grafast: {
      explain: false,
    },
    grafserv: {
      graphqlPath: "/graphql",
      graphiqlPath: "/graphiql",
      graphiql: true,
      maxRequestLength: 10000,
    },
  };

  const pgl = postgraphile(preset);
  const serv = pgl.createServ(grafserv);
  const app = fastify();
  await serv.addTo(app);
  return app;
}

// To run the server directly, you can use the following code:
const start = async () => {
  const fastify = await createApp({
    databaseConnectionString:
      "postgres://orcabus:orcabus@localhost:5432/metadata_manager", // pragma: allowlist secret`
  });

  try {
    await fastify.listen({ port: 5000 });
    console.log(`Server is running at http://localhost:5000`);
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
};
// start();

// For AWS Lambda, we export the handler function
exports.handler = async (event: any, context: any) => {
  const database_name = process.env.DATABASE_NAME;
  if (!database_name) {
    throw new Error("DATABASE_NAME environment variable is not set");
  }

  const secretString = await getSecretManagerValue();
  const secretJson = JSON.parse(secretString);
  console.log("the secret string is", secretJson);
  console.log("the host: ", secretJson.host);
  const dbConnectionString = constructDatabaseConnectionString({
    host: secretJson.host,
    port: secretJson.port,
    username: secretJson.username,
    password: secretJson.password,
    // We might connect different databases depending on the environment
    database: database_name,
  });
  console.log("the db connection string is", dbConnectionString);

  const app = await createApp({ databaseConnectionString: dbConnectionString });
  const proxy = awsLambdaFastify(app);

  return proxy(event, context);
};
