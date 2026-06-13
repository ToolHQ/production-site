const { spawn } = require("child_process");

// Start timestamp
const startTimestamp = new Date().toISOString();
console.log(`Process started at: ${startTimestamp}`);
const startTime = Date.now();

// Spawn the Python process
const pythonProcess = spawn("python3", ["process_data.py"]);

// Log Python script stdout as it streams
pythonProcess.stdout.on("data", (data) => {
  console.log(`Python script output: ${data}`);
});

// Log Python script stderr as it streams (e.g., warnings or errors)
pythonProcess.stderr.on("data", (data) => {
  console.error(`Python script error: ${data}`);
});

// When the Python process ends, log completion and elapsed time
pythonProcess.on("close", (code) => {
  const endTimestamp = new Date().toISOString();
  const elapsedTimeMinutes = (Date.now() - startTime) / 60000;

  console.log(`Python process completed with exit code ${code}`);
  console.log(`Process completed at: ${endTimestamp}`);
  console.log(`Total elapsed time: ${elapsedTimeMinutes.toFixed(2)} minutes`);
});
