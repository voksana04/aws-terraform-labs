const AWS = require("aws-sdk");
const dynamodb = new AWS.DynamoDB({ region: process.env.AWS_REGION, apiVersion: "2012-08-10" });

exports.handler = (event, context, callback) => {
  // Логуємо вхідні дані для відлагодження в CloudWatch
  console.log("Received event:", JSON.stringify(event, null, 2));

  const params = { 
    Key: { 
      id: { S: event.id } 
    }, 
    TableName: process.env.TABLE_NAME 
  };

  dynamodb.deleteItem(params, (err, data) => {
    if (err) {
      console.log("Error deleting item:", err);
      callback(null, {
        statusCode: 500,
        headers: { "Access-Control-Allow-Origin": "*" },
        body: JSON.stringify({ message: "Internal Server Error", error: err })
      });
    } else {
      console.log("Delete succeeded:", data);
      callback(null, {
        statusCode: 200,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*"
        },
        body: JSON.stringify({}) 
      });
    }
  });
};