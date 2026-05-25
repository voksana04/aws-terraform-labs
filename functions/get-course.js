const AWS = require("aws-sdk");
const dynamodb = new AWS.DynamoDB({ region: process.env.AWS_REGION, apiVersion: "2012-08-10" });

exports.handler = (event, context, callback) => {
  // Логуємо event, щоб бачити, як VTL-шаблон передав ID
  console.log("Received event:", JSON.stringify(event, null, 2));

  const params = { 
    Key: { 
      id: { S: event.id } 
    }, 
    TableName: process.env.TABLE_NAME 
  };

  dynamodb.getItem(params, (err, data) => {
    if (err) {
      console.log("DynamoDB error:", err);
      callback(null, {
        statusCode: 500,
        headers: { "Access-Control-Allow-Origin": "*" },
        body: JSON.stringify({ message: "Internal Server Error", error: err })
      });
    } else if (!data.Item) {
      // Якщо курсу з таким ID немає в базі
      callback(null, {
        statusCode: 404,
        headers: { "Access-Control-Allow-Origin": "*" },
        body: JSON.stringify({ message: "Course not found" })
      });
    } else {
      // Успішна відповідь
      const course = {
        id: data.Item.id.S,
        title: data.Item.title.S,
        watchHref: data.Item.watchHref.S,
        authorId: data.Item.authorId.S,
        length: data.Item.length.S,
        category: data.Item.category.S
      };

      callback(null, {
        statusCode: 200,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*"
        },
        body: JSON.stringify(course)
      });
    }
  });
};