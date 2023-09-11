
const express = require('express');
const bodyParser = require('body-parser');

const baseRoute = require('./routes/base');
const contractRoute = require('./routes/contract');
const messageRoute = require('./routes/messages');
const errors = require('./errors/errors')

const app = express();
const PORT = 3005;

app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: false }));

app.use('/', baseRoute);
app.use('/contract', contractRoute);
app.use('/messages', messageRoute);

app.listen(PORT, () => {
    console.log(`Server is running on http://localhost:${PORT}`);
});

app.use(errors);