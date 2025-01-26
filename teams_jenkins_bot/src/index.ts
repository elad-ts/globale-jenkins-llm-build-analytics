// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

// Import required packages
import { config } from 'dotenv';
import * as path from 'path';
import * as restify from 'restify';
import axios from 'axios'; // Import Axios

// Import required bot services.
// See https://aka.ms/bot-services to learn more about the different parts of a bot.
import { ActivityTypes, ConfigurationServiceClientCredentialFactory, MemoryStorage, TurnContext } from 'botbuilder';

import { Application, TurnState, TeamsAdapter } from '@microsoft/teams-ai';

// Read botFilePath and botFileSecret from .env file.
const ENV_FILE = path.join(__dirname, '..', '.env');
config({ path: ENV_FILE });

// Create adapter.
// See https://aka.ms/about-bot-adapter to learn more about how bots work.
const adapter = new TeamsAdapter(
    {},
    new ConfigurationServiceClientCredentialFactory({
        MicrosoftAppId: process.env.BOT_ID,
        MicrosoftAppPassword: process.env.BOT_PASSWORD,
        MicrosoftAppType: 'MultiTenant'
    })
);

// Catch-all for errors.
const onTurnErrorHandler = async (context: TurnContext, error: any) => {
    // This check writes out errors to console log .vs. app insights.
    // NOTE: In production environment, you should consider logging this to Azure
    //       application insights.
    console.error(`\n [onTurnError] unhandled error: ${error}`);
    console.log(error);

    // Send a trace activity, which will be displayed in Bot Framework Emulator
    await context.sendTraceActivity(
        'OnTurnError Trace',
        `${error}`,
        'https://www.botframework.com/schemas/error',
        'TurnError'
    );

    // Send a message to the user
    await context.sendActivity('The bot encountered an error or bug.');
    await context.sendActivity('To continue to run this bot, please fix the bot source code.');
};

// Set the onTurnError for the singleton CloudAdapter.
adapter.onTurnError = onTurnErrorHandler;

// Create HTTP server.
const server = restify.createServer();
server.use(restify.plugins.bodyParser());

server.listen(process.env.port || process.env.PORT || 3978, () => {
    console.log(`\n${server.name} listening to ${server.url}`);
    console.log('\nTo test your bot in Teams, sideload the app manifest.json within Teams Apps.');
});

interface ConversationState {
     history: string[]; // Maintain conversation history as an array of strings
}
type ApplicationTurnState = TurnState<ConversationState>;

// Define storage and application
const storage = new MemoryStorage();
const app = new Application<ApplicationTurnState>({
    storage
});

// Listen for user to say '/reset' and then delete conversation state
app.message('/reset', async (context: TurnContext, state: ApplicationTurnState) => {
    state.deleteConversationState();
    await context.sendActivity(`Ok I've deleted the current conversation state.`);
});

// Function to concatenate chat history with user input and apply trimming
function buildChatPrompt(history: string[], userPrompt: string, maxSizeK: number): string {
    const maxSize = maxSizeK * 1024; // Convert maxSizeK to characters
    let combinedText = [...history, userPrompt].join('\n');

    if (combinedText.length > maxSize) {
        // Trim history if the combined text exceeds the max size
        while (combinedText.length > maxSize && history.length > 0) {
            history.shift(); // Remove the oldest message
            combinedText = [...history, userPrompt].join('\n');
        }
    }

    return combinedText;
}


// Listen for ANY message to be received. MUST BE AFTER ANY OTHER MESSAGE HANDLERS
app.activity(ActivityTypes.Message, async (context: TurnContext, state: ApplicationTurnState) => {
     // Initialize conversation history if not already present
     if (!state.conversation.history) {
        state.conversation.history = [];
    }

    // Get the user's input
    const userPrompt = context.activity.text;

    // Add user input to the history
    state.conversation.history.push(`User: ${userPrompt}`);

    // Simulate bot response with a random quote
    let botResponse = 'Sorry, no response available.';
    try {
        const response = await axios.get('https://zenquotes.io/api/random', {
            headers: {
                Authorization: `Bearer YOUR_ACCESS_TOKEN`
            }
        });
        const quote = response.data[0]?.q; // Extract the quote
        const author = response.data[0]?.a; // Extract the author
        botResponse = `Here is your random quote: "${quote}" - ${author}`;
    } catch (error) {
        console.error('Error fetching quote:', error);
        botResponse = 'Failed to fetch a quote. Please try again later.';
    }

    // Add bot response to the history
    state.conversation.history.push(`Bot: ${botResponse}`);

    // Build the prompt with the full conversation history and the current input
    const maxSizeK = 4; // Define the max string size in KB
    const combinedPrompt = buildChatPrompt(state.conversation.history, userPrompt, maxSizeK);

    // Respond to the user
    await context.sendActivity(botResponse);

    // For debugging, you can log the combined prompt
    console.log('Combined Prompt:', combinedPrompt);
});

// Listen for incoming server requests.
server.post('/api/messages', async (req, res) => {
    // Route received a request to adapter for processing
    await adapter.process(req, res as any, async (context) => {
        // Dispatch to application for routing
        await app.run(context);
    });
});
