#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
	CallToolRequestSchema,
	ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";
import net from "net";

const LOVE2D_HOST = "localhost";
const LOVE2D_PORT = 12345;

// TCP client to communicate with LÖVE2D game
class Love2DClient {
	private client: net.Socket | null = null;
	private connecting: boolean = false;
	private retryDelay: number = 500;
	private readonly maxRetryDelay: number = 5000;

	async connect(): Promise<void> {
		if (this.connecting) {
			// Wait for existing connection attempt
			while (this.connecting) {
				await new Promise((r) => setTimeout(r, 100));
			}
			if (this.client) return;
		}

		this.connecting = true;
		this.retryDelay = 500;

		try {
			await this.attemptConnect();
		} finally {
			this.connecting = false;
		}
	}

	private attemptConnect(): Promise<void> {
		return new Promise((resolve, reject) => {
			const tryConnect = () => {
				const sock = net.createConnection(
					{ host: LOVE2D_HOST, port: LOVE2D_PORT },
					() => {
						console.error("Connected to LÖVE2D game");
						this.client = sock;
						this.retryDelay = 500;
						this.setupKeepAlive(sock);
						this.setupDataHandler(sock);
						resolve();
					},
				);

				sock.on("error", (err) => {
					console.error("TCP connection error:", err.message);
					sock.destroy();

					// Retry with backoff
					if (this.retryDelay < this.maxRetryDelay) {
						this.retryDelay = Math.min(this.retryDelay * 2, this.maxRetryDelay);
					}
					setTimeout(tryConnect, this.retryDelay);
				});

				sock.on("close", () => {
					if (this.client === sock) {
						console.error("TCP connection to game lost");
						this.client = null;
					}
				});
			};

			tryConnect();
		});
	}

	private setupKeepAlive(sock: net.Socket): void {
		sock.on("close", () => {
			if (this.client === sock) {
				console.error(
					"TCP connection to game lost, will reconnect on next command",
				);
				this.client = null;
			}
		});

		sock.on("error", (err) => {
			console.error("TCP socket error:", err.message);
		});
	}

	// Serialize TCP commands: only one in-flight at a time
	private commandQueue: Array<{
		command: any;
		resolve: (v: any) => void;
		reject: (e: Error) => void;
	}> = [];
	private processing: boolean = false;
	// Buffer for TCP data that may arrive in chunks
	private dataBuffer: string = "";
	private pendingResponse: {
		resolve: (v: any) => void;
		reject: (e: Error) => void;
	} | null = null;

	private setupDataHandler(sock: net.Socket): void {
		sock.on("data", (buffer: Buffer) => {
			this.dataBuffer += buffer.toString();

			// Process complete JSON lines from the buffer
			while (this.dataBuffer.includes("\n")) {
				const newlineIdx = this.dataBuffer.indexOf("\n");
				const line = this.dataBuffer.slice(0, newlineIdx);
				this.dataBuffer = this.dataBuffer.slice(newlineIdx + 1);

				if (!line.trim()) continue;

				try {
					const response = JSON.parse(line);
					const pr = this.pendingResponse;
					if (pr) {
						this.pendingResponse = null;
						pr.resolve(response);
						this.processNext();
					}
				} catch (err) {
					const pr = this.pendingResponse;
					if (pr) {
						this.pendingResponse = null;
						pr.reject(err instanceof Error ? err : new Error(String(err)));
						this.processNext();
					}
				}
			}
		});
	}

	private async processNext(): Promise<void> {
		if (this.processing || this.commandQueue.length === 0) return;
		this.processing = true;

		while (this.commandQueue.length > 0) {
			const item = this.commandQueue[0];
			if (!item) break;

			if (!this.client) {
				this.commandQueue.shift();
				item.reject(new Error("Not connected to LÖVE2D game"));
				continue;
			}

			const data = JSON.stringify(item.command) + "\n";

			await new Promise<void>((resolveWrite, rejectWrite) => {
				this.client!.write(data, (err) => {
					if (err) {
						this.commandQueue.shift();
						rejectWrite(err);
					} else {
						resolveWrite();
					}
				});
			});

			// Wait for response (removes item from queue in setupDataHandler)
			await new Promise<void>((resolveResponse, rejectResponse) => {
				this.pendingResponse = {
					resolve: (v: any) => {
						this.commandQueue.shift();
						item.resolve(v);
						resolveResponse();
					},
					reject: (e: Error) => {
						this.commandQueue.shift();
						item.reject(e);
						resolveResponse();
					},
				};
			});
		}

		this.processing = false;
	}

	async sendCommand(command: any): Promise<any> {
		if (!this.client) {
			await this.connect();
		}

		return new Promise((resolve, reject) => {
			this.commandQueue.push({ command, resolve, reject });
			if (!this.processing) {
				this.processNext();
			}
		});
	}

	disconnect(): void {
		if (this.client) {
			this.client.end();
			this.client = null;
		}
	}
}

const love2dClient = new Love2DClient();

// Create MCP server
const server = new Server(
	{
		name: "love2d-mcp",
		version: "1.0.0",
	},
	{
		capabilities: {
			tools: {},
		},
	},
);

// List available tools
server.setRequestHandler(ListToolsRequestSchema, async () => {
	return {
		tools: [
			{
				name: "list_objects",
				description: "List all objects in the current game scene",
				inputSchema: {
					type: "object",
					properties: {},
				},
			},
			{
				name: "get_object",
				description: "Get detailed information about a specific object by ID",
				inputSchema: {
					type: "object",
					properties: {
						id: {
							type: "string",
							description: "The ID of the object to retrieve",
						},
					},
					required: ["id"],
				},
			},
			{
				name: "run_lua",
				description:
					"Execute arbitrary Lua code in the game context with access to 'love', 'objects', and standard Lua libraries. Return values are JSON-encoded.",
				inputSchema: {
					type: "object",
					properties: {
						code: {
							type: "string",
							description: "The Lua code to execute",
						},
					},
					required: ["code"],
				},
			},
			{
				name: "add_object",
				description:
					"Create a new game object with a specified type and properties. Returns the created object with its auto-generated ID.",
				inputSchema: {
					type: "object",
					properties: {
						type: {
							type: "string",
							description:
								"The type of object to create (e.g., 'ball', 'player', 'wall')",
						},
						properties: {
							type: "object",
							description:
								"Initial property values for the object (e.g., x, y, vx, vy, radius, r, g, b)",
						},
					},
					required: ["type"],
				},
			},
			{
				name: "remove_object",
				description: "Remove a game object by its ID.",
				inputSchema: {
					type: "object",
					properties: {
						id: {
							type: "string",
							description: "The ID of the object to remove",
						},
					},
					required: ["id"],
				},
			},
			{
				name: "modify_object",
				description:
					"Modify properties of an existing game object. Provide only the properties you want to change.",
				inputSchema: {
					type: "object",
					properties: {
						id: {
							type: "string",
							description: "The ID of the object to modify",
						},
						properties: {
							type: "object",
							description:
								"Properties to update on the object (e.g., x, y, vx, vy, r, g, b)",
						},
					},
					required: ["id", "properties"],
				},
			},
			{
				name: "get_game_state",
				description:
					"Get comprehensive game state including window dimensions, FPS, object count, list of objects, LÖVE2D version, and pause state.",
				inputSchema: {
					type: "object",
					properties: {},
				},
			},
			{
				name: "pause_game",
				description:
					"Pause or unpause the game loop. When paused, love.update() skips all game logic while still processing MCP commands.",
				inputSchema: {
					type: "object",
					properties: {
						paused: {
							type: "boolean",
							description: "true to pause, false to resume",
						},
					},
					required: ["paused"],
				},
			},
			{
				name: "get_performance_stats",
				description:
					"Get current performance statistics including FPS, object count, delta time, and elapsed game time.",
				inputSchema: {
					type: "object",
					properties: {},
				},
			},
			{
				name: "create_debug_text",
				description:
					"Display a text overlay on the game screen for debugging purposes. Text auto-removes after 10 seconds.",
				inputSchema: {
					type: "object",
					properties: {
						text: {
							type: "string",
							description: "The text to display",
						},
						x: {
							type: "number",
							description: "X position on screen (default: 10)",
						},
						y: {
							type: "number",
							description:
								"Y position on screen (default: near bottom of window)",
						},
						color: {
							type: "object",
							description: "RGB color for the text",
							properties: {
								r: { type: "number", description: "Red component 0-1" },
								g: { type: "number", description: "Green component 0-1" },
								b: { type: "number", description: "Blue component 0-1" },
							},
						},
					},
					required: ["text"],
				},
			},
			{
				name: "capture_screenshot",
				description:
					"Capture a screenshot of the current game frame and save it to the game's save directory.",
				inputSchema: {
					type: "object",
					properties: {},
				},
			},
		],
	};
});

// Handle tool calls
server.setRequestHandler(CallToolRequestSchema, async (request) => {
	const { name, arguments: args } = request.params;

	try {
		switch (name) {
			case "list_objects": {
				const response = await love2dClient.sendCommand({
					command: "list_objects",
				});
				return {
					content: [
						{
							type: "text",
							text: JSON.stringify(response, null, 2),
						},
					],
				};
			}

			case "get_object": {
				const objectId = (args as any).id;
				const response = await love2dClient.sendCommand({
					command: "get_object",
					id: objectId,
				});
				return {
					content: [
						{
							type: "text",
							text: JSON.stringify(response, null, 2),
						},
					],
				};
			}

			case "run_lua": {
				const code = (args as any).code;
				const response = await love2dClient.sendCommand({
					command: "run_lua",
					code: code,
				});
				return {
					content: [
						{
							type: "text",
							text: JSON.stringify(response, null, 2),
						},
					],
				};
			}

			case "add_object": {
				const { type: objType, properties } = args as any;
				const response = await love2dClient.sendCommand({
					command: "add_object",
					type: objType,
					properties: properties || {},
				});
				return {
					content: [
						{
							type: "text",
							text: JSON.stringify(response, null, 2),
						},
					],
				};
			}

			case "remove_object": {
				const { id } = args as any;
				const response = await love2dClient.sendCommand({
					command: "remove_object",
					id,
				});
				return {
					content: [
						{
							type: "text",
							text: JSON.stringify(response, null, 2),
						},
					],
				};
			}

			case "modify_object": {
				const { id: modId, properties } = args as any;
				const response = await love2dClient.sendCommand({
					command: "modify_object",
					id: modId,
					properties,
				});
				return {
					content: [
						{
							type: "text",
							text: JSON.stringify(response, null, 2),
						},
					],
				};
			}

			case "get_game_state": {
				const response = await love2dClient.sendCommand({
					command: "get_game_state",
				});
				return {
					content: [
						{
							type: "text",
							text: JSON.stringify(response, null, 2),
						},
					],
				};
			}

			case "pause_game": {
				const { paused } = args as any;
				const response = await love2dClient.sendCommand({
					command: "pause_game",
					paused,
				});
				return {
					content: [
						{
							type: "text",
							text: JSON.stringify(response, null, 2),
						},
					],
				};
			}

			case "get_performance_stats": {
				const response = await love2dClient.sendCommand({
					command: "get_performance_stats",
				});
				return {
					content: [
						{
							type: "text",
							text: JSON.stringify(response, null, 2),
						},
					],
				};
			}

			case "create_debug_text": {
				const { text, x, y, color } = args as any;
				const response = await love2dClient.sendCommand({
					command: "set_debug_text",
					text,
					x,
					y,
					color: color || null,
				});
				return {
					content: [
						{
							type: "text",
							text: JSON.stringify(response, null, 2),
						},
					],
				};
			}

			case "capture_screenshot": {
				const response = await love2dClient.sendCommand({
					command: "capture_screenshot",
				});
				return {
					content: [
						{
							type: "text",
							text: JSON.stringify(response, null, 2),
						},
					],
				};
			}

			default:
				throw new Error(`Unknown tool: ${name}`);
		}
	} catch (error) {
		return {
			content: [
				{
					type: "text",
					text: `Error: ${error instanceof Error ? error.message : String(error)}`,
				},
			],
			isError: true,
		};
	}
});

// Start the server
async function main() {
	const transport = new StdioServerTransport();
	await server.connect(transport);
	console.error("LÖVE2D MCP server running on stdio");
}

main().catch((error) => {
	console.error("Fatal error:", error);
	process.exit(1);
});
