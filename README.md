# SurvivorCore

SurvivorCore is an open-source survival game framework for OpenSimulator regions. It provides a modular system for creating immersive survival experiences, including player stats, zombie interactions, crafting, and quest systems. The framework is designed to be highly customizable and easy to use.

## Features

- **Player Statistics System**: Track health, hunger, thirst, stamina, and infection levels
- **Zombie AI**: Configurable zombie behavior and interactions
- **Crafting System**: Create items from gathered resources
- **Quest System**: Implement missions and objectives for players
- **Consumable Items**: Food, drinks, medical supplies with configurable effects
- **Modular Design**: Easy to extend and customize for your specific needs

## Installation

1. Download the latest release from the [releases page](https://github.com/TemujinCalidius/SurvivorCore/releases)
2. Import the scripts into your OpenSimulator region
3. Configure the settings according to your preferences

## Usage

### Basic Setup

1. Add the SurvivorCore scripts to your region's objects
2. Configure the communication channels in the scripts
3. Set up player HUDs and meters
4. Create consumable items with appropriate descriptions

### Creating Consumables

Consumables use a simple description format to define their effects:
Food 20, Drink 10, Health 5, Stamina 15, Potion 25, Uses 3

- **Food**: Reduces hunger
- **Drink**: Reduces thirst
- **Health**: Restores health points
- **Stamina**: Restores stamina
- **Potion**: Reduces infection (value determines effectiveness)
- **Uses**: Number of times the item can be used

### Infection System

The infection system simulates disease progression:
- Infection levels range from 0-100
- Once infected, the level increases over time
- At 100%, infection damages health and stamina
- Use medical items (Potion value) to reduce infection levels

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

- **Temujin Calidius** - *Initial work* - [TemujinCalidius](https://github.com/TemujinCalidius)

## Acknowledgments

- Thanks to the OpenSimulator community for their support
- Special thanks to all contributors who have helped shape this project

