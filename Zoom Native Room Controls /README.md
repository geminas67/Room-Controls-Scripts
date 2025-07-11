# 🎥 Zoom Visualizer - Local

A local web-based visualizer for testing Zoom room control configurations, designed to run entirely within Cursor.

## 🚀 Quick Start

### Option 1: Using Node.js Server (Recommended)
```bash
# Start the server
npm start

# Or directly with node
node server.js
```

Then open: **http://localhost:3000**

### Option 2: Using Python Server
```bash
# Start Python server
python3 -m http.server 8000
```

Then open: **http://localhost:8000/zoom_visualizer.html**

### Option 3: Direct File Opening
Simply double-click `zoom_visualizer.html` to open in your default browser.

## 📋 Features

- **Drag & Drop JSON Upload** - Upload your room control configurations
- **Interactive Controls** - Click to test control states
- **Configuration Summary** - View adapter counts and details
- **JSON Viewer** - See full configuration in formatted view
- **Status Indicators** - Monitor connection and configuration status
- **Sample Configuration** - Pre-loaded with UNC Giles - Sycamore setup

## 🎯 Usage

1. **Upload Configuration**: Drag your JSON file onto the upload area
2. **Test Controls**: Click any control button to cycle through states
3. **View Details**: Check the sidebar for configuration summary
4. **Export**: Use the JSON viewer to copy configurations

## 📁 File Structure

```
Room Controls Scripts/
├── zoom_visualizer.html    # Main visualizer interface
├── server.js              # Node.js server
├── package.json           # Node.js configuration
└── README.md             # This file
```

## 🔧 Customization

The visualizer automatically loads your UNC Giles configuration as a sample. To customize:

1. Edit the `loadSampleConfig()` function in `zoom_visualizer.html`
2. Replace the sample configuration with your own
3. Modify the styling in the `<style>` section

## 🎨 Integration with Cursor

- **Live Editing**: Edit the HTML file and refresh the browser to see changes
- **Terminal Integration**: Run the server directly in Cursor's terminal
- **File Watching**: The server will serve any files in the directory

## 🚨 Troubleshooting

- **Port already in use**: Change the PORT variable in `server.js`
- **File not found**: Ensure you're in the correct directory
- **CORS issues**: The local server handles this automatically

## 📝 License

MIT License - Feel free to modify and use as needed. 