const AWS = require("aws-sdk");
const dynamodb = new AWS.DynamoDB({ region: process.env.AWS_REGION, apiVersion: "2012-08-10" });

const replaceAll = (str, find, replace) => { 
  if (!str) return "";
  return str.replace(new RegExp(find, "g"), replace); 
};

exports.handler = (event, context, callback) => {
  // Логуємо вхідний об'єкт, щоб перевірити роботу валідатора
  console.log("Received event:", JSON.stringify(event, null, 2));

  const title = event.title || "default-title";
  const id = replaceAll(title, " ", "-").toLowerCase();
  
  const params = {
    Item: {
      id: { S: id },
      title: { S: title },
      watchHref: { S: `http://www.pluralsight.com/courses/${id}` },
      authorId: { S: event.authorId || "" },
      length: { S: event.length || "" },
      category: { S: event.category || "" }
    },
    TableName: process.env.TABLE_NAME
  };

  dynamodb.putItem(params, (err, data) => {
    if (err) { 
      console.log("Error saving item:", err); 
      callback(null, {
        statusCode: 500,
        headers: { "Access-Control-Allow-Origin": "*" },
        body: JSON.stringify({ message: "Could not save course", error: err })
      });
    } 
    else {
      // Створюємо об'єкт відповіді
      const responseBody = {
        id: params.Item.id.S,
        title: params.Item.title.S,
        watchHref: params.Item.watchHref.S,
        authorId: params.Item.authorId.S,
        length: params.Item.length.S,
        category: params.Item.category.S
      };

      callback(null, {
        statusCode: 201, 
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*"
        },
        body: JSON.stringify(responseBody)
      });
    }
  });
};