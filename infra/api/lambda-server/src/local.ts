import { createApp } from "./postgraphile";

const start = async () => {
  const fastify = await createApp({
    databaseConnectionString:
      process.env.DATABASE_URL ||
      "postgres://orcabus:orcabus@localhost:5432/metadata_manager", // pragma: allowlist secret`
  });

  try {
    await fastify.listen({ port: 5000 });
    console.log(`Server is running at http://localhost:5000/graphiql`);
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
};
start();
