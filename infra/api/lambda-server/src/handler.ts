import awsLambdaFastify from "@fastify/aws-lambda";
import { constructDatabaseConnectionString, createApp } from "./postgraphile";

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
  const bodyText = await response.text();
  return JSON.parse(bodyText).SecretString;
}

exports.handler = async (event: any, context: any) => {
  const database_name = process.env.DATABASE_NAME;
  if (!database_name) {
    throw new Error("DATABASE_NAME environment variable is not set");
  }

  const secretString = await getSecretManagerValue();
  const secretJson = JSON.parse(secretString);
  const dbConnectionString = constructDatabaseConnectionString({
    host: secretJson.host,
    port: secretJson.port,
    username: secretJson.username,
    // We encode the password to ensure it is safe for URL usage
    password: encodeURIComponent(secretJson.password),
    // We might connect different databases depending on the environment
    database: database_name,
  });

  const app = await createApp({ databaseConnectionString: dbConnectionString });
  const proxy = awsLambdaFastify(app);

  return proxy(event, context);
};
