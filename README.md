# Audio Router Controller (Python)

A Python implementation of the Q-SYS Audio Router Controller, providing class-based audio routing management for professional audio systems.

## Overview

This Python version maintains the simplicity and functionality of the original Lua implementation while following Python best practices. It provides:

- **Component Discovery**: Automatic discovery of audio router and room control components
- **Audio Routing**: Manual and automatic routing between inputs and outputs
- **Room Integration**: Integration with room control systems for automatic routing based on system state
- **Event Handling**: Comprehensive event handling for real-time system updates
- **Error Handling**: Robust error handling and validation
- **Logging**: Configurable logging for debugging and monitoring

## Features

- **Type Safety**: Full type hints for better code maintainability
- **Configuration Management**: Flexible configuration system
- **Enumeration Support**: Strongly typed enums for inputs, outputs, and component types
- **Event-Driven Architecture**: Clean event handling system
- **Resource Management**: Proper cleanup and resource management
- **Mock Support**: Built-in mock components for testing and development

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd audio-router-controller
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

3. For development, install additional dependencies:
```bash
pip install -r requirements.txt[dev]
```

## Usage

### Basic Usage

```python
from audio_router_controller import AudioRouterController, ControllerConfig

# Create a controller with default configuration
controller = AudioRouterController()

# Or with custom configuration
config = ControllerConfig(debugging=True, clear_string="[Clear]")
controller = AudioRouterController(config)

# Set a route manually
controller.set_route(1, 1)  # Set Output 1 to Input 1

# Clean up when done
controller.cleanup()
```

### Using the Factory Function

```python
from audio_router_controller import create_audio_router_controller

# Create controller using factory function
controller = create_audio_router_controller()

if controller:
    # Controller created successfully
    controller.set_route(2, 1)  # Set Output 1 to Input 2
else:
    print("Failed to create controller")
```

### Configuration

```python
from audio_router_controller import ControllerConfig

# Custom configuration
config = ControllerConfig(
    debugging=True,        # Enable debug logging
    clear_string="[Clear]" # Custom clear string
)

controller = AudioRouterController(config)
```

### Component Management

```python
# Discover available components
controller.discover_components()

# Set up audio router component
controller.set_audio_router_component()

# Set up room controls component
controller.set_room_controls_component()

# Check component status
controller.check_status()
```

## Architecture

### Class Structure

- **AudioRouterController**: Main controller class
- **ControllerConfig**: Configuration dataclass
- **ComponentType**: Enum for component types
- **InputType**: Enum for input types
- **OutputType**: Enum for output types

### Key Methods

- `set_route(input_val, output_val)`: Set audio routing
- `discover_components()`: Discover available components
- `set_audio_router_component()`: Configure audio router
- `set_room_controls_component()`: Configure room controls
- `cleanup()`: Clean up resources

## Q-SYS Integration

This Python implementation is designed to work with Q-SYS systems. The original Lua code was specifically designed for Q-SYS firmware 10.0.0+. 

### Key Differences from Lua Version

1. **Type Safety**: Python version includes comprehensive type hints
2. **Error Handling**: More robust error handling with try/catch blocks
3. **Logging**: Structured logging instead of print statements
4. **Configuration**: Dataclass-based configuration management
5. **Mock Components**: Built-in mock components for testing

### Q-SYS Specific Notes

- The `Controls` object references are mocked in this Python version
- Component discovery uses mock data instead of `Component.GetComponents()`
- Event handlers are adapted for Python's event system
- Q-SYS specific APIs would need to be implemented for actual deployment

## Development

### Running Tests

```bash
# Run all tests
pytest

# Run with coverage
pytest --cov=audio_router_controller

# Run specific test file
pytest test_audio_router_controller.py
```

### Code Quality

```bash
# Format code
black audio_router_controller.py

# Lint code
flake8 audio_router_controller.py

# Type checking
mypy audio_router_controller.py
```

### Project Structure

```
audio-router-controller/
├── audio_router_controller.py  # Main implementation
├── requirements.txt            # Dependencies
├── README.md                   # This file
├── tests/                      # Test files
│   └── test_audio_router_controller.py
└── examples/                   # Usage examples
    └── basic_usage.py
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Original Lua implementation by Nikolas Smith, Q-SYS
- Q-SYS platform for professional audio systems
- Python community for best practices and tools

## Version History

- **1.0**: Initial Python conversion from Lua
  - Class-based architecture
  - Type hints and enums
  - Configuration management
  - Mock component support
  - Comprehensive documentation 