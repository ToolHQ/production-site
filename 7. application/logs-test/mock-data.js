const { Client } = require("@elastic/elasticsearch");
const { faker } = require("@faker-js/faker");
const { Agent } = require("undici"); // Use undici Agent

// Load environment variables for Elasticsearch credentials
const ELASTIC_USER = process.env.ELASTIC_USER;
const ELASTIC_PASSWORD = process.env.ELASTIC_PASSWORD;

const client = new Client({
  node: "https://es.localhost",
  auth: {
    username: ELASTIC_USER,
    password: ELASTIC_PASSWORD,
  },
  tls: {
    rejectUnauthorized: false, // Allow self-signed certificates
  },
  agent: new Agent({
    keepAliveTimeout: 10000,
    keepAliveMaxTimeout: 10000,
    rejectUnauthorized: false, // Allow self-signed certificates
  }),
});

// Define data stream name
const dataStreamName = "logspoc";

async function createDataStream() {
  // Purge data stream if it exists
  try {
    await client.indices.deleteDataStream({ name: dataStreamName });
    console.log(`Data stream ${dataStreamName} deleted.`);
  } catch (err) {
    if (err.meta && err.meta.statusCode === 404) {
      console.log(
        `Data stream ${dataStreamName} not found, proceeding to creation.`
      );
    } else {
      console.error("Error deleting data stream:", err);
      return; // Stop the script if another error occurs
    }
  }

  // Create the data stream
  try {
    await client.indices.createDataStream({ name: dataStreamName });
    console.log(`Data stream ${dataStreamName} created.`);
  } catch (err) {
    console.error("Error creating data stream:", err);
    if (
      err.meta &&
      err.meta.body &&
      err.meta.body.error.type === "illegal_state_exception"
    ) {
      console.error(
        "It seems that the data stream timestamp field is disabled."
      );
    }
    return;
  }
}

function generateLogEntry() {
  return {
    userLogin: faker.internet.userName(),
    userId: faker.number.int({ min: 1, max: 999999 }), // Corrected method
    "@timestamp": new Date().toISOString(), // Required for data streams
    httpPath: faker.internet.url(),
    httpMethod: faker.helpers.arrayElement(["GET", "POST", "PUT", "DELETE"]),
    httpQuery: faker.datatype.boolean() ? faker.person.fullName() : null, // Updated to use person.fullName
    httpStatus: faker.helpers.arrayElement([200, 201, 401, 404, 500]),
    elapsedTime: faker.number.int({ min: 50, max: 1000 }), // Corrected method
    accountNumber: faker.finance.accountNumber(), // Updated to use accountNumber
  };
}

async function populateData() {
  const bulkSize = 1000; // How many records per bulk request
  const totalRecords = 10000000; // 10 million records
  const totalBatches = totalRecords / bulkSize; // Total number of bulk requests (each containing bulkSize records)
  let progressPercentage = 0; // To track the progress percentage

  // Start timestamp
  const startTimestamp = new Date().toISOString();
  console.log(`Data population started at: ${startTimestamp}`);

  const startTime = Date.now(); // For elapsed time calculation

  for (let i = 0; i < totalBatches; i++) {
    const bulkOperations = [];

    // Generate bulkSize records for this batch
    for (let j = 0; j < bulkSize; j++) {
      const logEntry = generateLogEntry();
      bulkOperations.push({ create: { _index: dataStreamName } });
      bulkOperations.push(logEntry);
    }

    // Send the bulk request to Elasticsearch
    await client.bulk({ refresh: true, body: bulkOperations });

    // Calculate progress percentage
    const currentPercentage = Math.floor(((i + 1) / totalBatches) * 100);

    // Log the progress when the percentage changes
    if (currentPercentage > progressPercentage) {
      progressPercentage = currentPercentage;
      console.log(`Progress: ${progressPercentage}%`);
    }
  }

  // End timestamp and elapsed time
  const endTimestamp = new Date().toISOString();
  const elapsedTimeMinutes = (Date.now() - startTime) / 60000; // Convert from milliseconds to minutes

  // Log process information
  console.log("Data population completed.");
  console.log(`Data population ended at: ${endTimestamp}`);
  console.log(`Total elapsed time: ${elapsedTimeMinutes.toFixed(2)} minutes`);
}

(async function () {
  try {
    await createDataStream();
    await populateData();
  } catch (err) {
    console.error("Error:", err);
  }
})();
