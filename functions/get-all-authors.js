const AWS = require("aws-sdk");
const docClient = new AWS.DynamoDB.DocumentClient({
  region: process.env.AWS_REGION
});

exports.handler = (event, context, callback) => {
  const params = { TableName: process.env.TABLE_NAME };
  
  docClient.scan(params, (err, data) => {
    if (err) {
      console.log(err);
      callback(err);
    } else {
      const authors = data.Items.map(item => ({
        id: item.id || "",
        firstName: item.firstName || "",
        lastName: item.lastName || ""
      }));
      callback(null, authors);
    }
  });
};
