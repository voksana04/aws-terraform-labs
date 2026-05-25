const AWS = require("aws-sdk");
const dynamodb = new AWS.DynamoDB({ region: process.env.AWS_REGION, apiVersion: "2012-08-10" });

exports.handler = (event, context, callback) => {
  // Логування вхідних даних для відлагодження
  console.log("Input event:", JSON.stringify(event, null, 2));

  const params = {
    Item: {
      // id приходить з URL через VTL шаблон (event.id)
      id: { S: event.id || "default-id" }, 
      title: { S: event.title || "" }, 
      watchHref: { S: event.watchHref || "" },
      authorId: { S: event.authorId || "" }, 
      length: { S: event.length || "" }, 
      category: { S: event.category || "" }
    },
    TableName: process.env.TABLE_NAME
  };

  dynamodb.putItem(params, (err, data) => {
    if (err) { 
      console.log("DynamoDB Error:", err); 
      // Відповідь у разі помилки
      callback(null, {
        statusCode: 500,
        headers: { "Access-Control-Allow-Origin": "*" },
        body: JSON.stringify({ message: "Could not update course", error: err })
      });
    } 
    else {
      console.log("Update Success:", data);
      
      // Формуємо об'єкт для тіла відповіді
      const updatedCourse = {
        id: params.Item.id.S,
        title: params.Item.title.S,
        watchHref: params.Item.watchHref.S,
        authorId: params.Item.authorId.S,
        length: params.Item.length.S,
        category: params.Item.category.S
      };

      // Успішна відповідь для API Gateway
      callback(null, {
        statusCode: 200,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*"
        },
        body: JSON.stringify(updatedCourse)
      });
    }
  });
};