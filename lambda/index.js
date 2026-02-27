exports.handler = async (event) => {
    console.log("S3 Event Received:");
    console.log(JSON.stringify(event, null, 2));

    if (event.Records) {
        for (const record of event.Records) {
            console.log("File uploaded:", record.s3.object.key);
        }
    }

    return {
        statusCode: 200,
        body: "Lambda executed successfully"
    };
};