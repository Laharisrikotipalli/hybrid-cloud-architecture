const express = require("express");
const AWS = require("aws-sdk");
const { Storage } = require("@google-cloud/storage");
const { Client } = require("pg");

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 8080;

let dbStatus = "Not Connected";

const pgClient = new Client({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: "hybrid_db",
  port: 5432,
});

pgClient.connect()
  .then(() => {
    console.log("Connected to PostgreSQL");
    dbStatus = "Connected to PostgreSQL";
  })
  .catch((err) => {
    console.error("PostgreSQL Error:", err);
    dbStatus = "Database Connection Failed";
  });



const sqs = new AWS.SQS({
  endpoint: process.env.AWS_ENDPOINT_URL,
  region: "us-east-1",
  accessKeyId: "test",
  secretAccessKey: "test",
  sslEnabled: false,
  s3ForcePathStyle: true
});

const s3 = new AWS.S3({
  endpoint: process.env.AWS_ENDPOINT_URL,
  s3ForcePathStyle: true,
  region: "us-east-1",
  accessKeyId: "test",
  secretAccessKey: "test"
});



const storage = new Storage();



app.get("/", (req, res) => {
  res.send(`
    <h1>Hybrid Cloud App Running</h1>
    <p><strong>PostgreSQL Status:</strong> ${dbStatus}</p>
    <p><strong>AWS Endpoint:</strong> ${process.env.AWS_ENDPOINT_URL}</p>
    <p><strong>SQS Queue URL:</strong> ${process.env.SQS_QUEUE_URL}</p>
    <p><strong>GCS Bucket:</strong> ${process.env.BUCKET_NAME}</p>
  `);
});

app.post("/send-message", async (req, res) => {
  try {
    const { message } = req.body;

    if (!message) {
      return res.status(400).json({ error: "Message is required" });
    }

    await sqs.sendMessage({
      QueueUrl: process.env.SQS_QUEUE_URL,
      MessageBody: message
    }).promise();

    res.status(202).json({ status: "Message sent to SQS" });

  } catch (err) {
    console.error("SQS Error:", err);
    res.status(500).json({ error: "Failed to send message", details: err.message });
  }
});

app.post("/trigger-pipeline", async (req, res) => {
  try {
    const { s3_object_key } = req.body;

    if (!s3_object_key) {
      return res.status(400).json({ error: "s3_object_key is required" });
    }

    console.log("Fetching from S3:", s3_object_key);

    const s3Object = await s3.getObject({
      Bucket: process.env.LOCALSTACK_S3_BUCKET,
      Key: s3_object_key
    }).promise();

    console.log("Uploading to GCS:", process.env.BUCKET_NAME);

    await storage
      .bucket(process.env.BUCKET_NAME)
      .file(s3_object_key)
      .save(s3Object.Body);

    res.status(200).json({ status: "File transferred to GCS" });

  } catch (err) {
    console.error("Pipeline Error:", err);
    res.status(500).json({ error: "Pipeline failed", details: err.message });
  }
});
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});