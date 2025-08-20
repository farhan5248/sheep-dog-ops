# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with the sheep-dog-ops repository.

> **📚 Complete Documentation**: See the comprehensive guidance files:
> - `../sheep-dog-main/CLAUDE.md` - Cross-repository coordination
> - `CLAUDE.architecture.md` - System architecture & design patterns
> - `CLAUDE.development.md` - Development workflows & practices  
> - `CLAUDE.testing.md` - BDD/testing methodologies

## Repository Overview

**sheep-dog-ops** provides **operations and release management** tools for the sheep-dog ecosystem.

### Key Components
- **sheep-dog-mgmt-maven-plugin**: Management Maven plugin for release coordination
- **Reusable GitHub Actions Workflows**: CI/CD automation workflows for other repositories
- **Container Operations**: Docker and Kubernetes reference commands

### Maven Plugin Provided
- **Plugin**: `sheep-dog-mgmt-maven-plugin:1.15-SNAPSHOT`
- **Purpose**: Release management and version coordination across repositories
- **Usage**: Used by other repositories for standardized release processes

## Operations Commands

### Building This Repository
```bash
mvn clean install
```

### Release Management
```bash
# Run from sheep-dog-mgmt-maven-plugin directory
scripts/install.bat
scripts/release.bat

# Or manually:
mvn clean install
mvn release:prepare release:perform
```

## Repository-Specific Features

### GitHub Actions Integration
- **Reusable Workflows**: Provides standardized CI/CD workflows for other sheep-dog repositories
- **Release Workflows**: Automated Maven release processes
- **Deploy Workflows**: Automated deployment to GitHub Packages

### Release Management
- **Version Coordination**: Manages version bumps across the ecosystem
- **Tag Management**: Standardized tagging for Maven modules
- **Deployment Orchestration**: Coordinates releases to GitHub Packages

### Container Operations Reference
The `cheatsheet.txt` provides reference commands for:
- **Docker**: Container management and image building
- **Docker Compose**: Multi-container development environments
- **Kubernetes**: Cluster management and deployment
- **Minikube**: Local Kubernetes development

## Ecosystem Coordination Role

### Build Order Position
This repository is **first** in the build order:
1. **sheep-dog-ops** → 2. **sheep-dog-qa** → 3. **sheep-dog-local** → 4. **sheep-dog-cloud**

### Dependencies Provided
- **Management Plugin**: Used by other repositories for release management
- **CI/CD Workflows**: GitHub Actions workflows referenced by other repositories
- **Container Standards**: Reference configurations for Docker and Kubernetes

### Cross-Repository Integration
- **Release Coordination**: Manages version bumps and releases across all repositories
- **Workflow Standardization**: Provides consistent CI/CD patterns
- **Operations Documentation**: Central location for infrastructure commands

## GitHub Actions Workflows

### Workflow Types
1. **Maven Release Workflows**: Run on `main` branch for tagging Maven modules
2. **Deploy Workflows**: Run on `develop` branch for deploying snapshots
3. **Reusable Workflows**: Shared workflow templates for other repositories

### Usage by Other Repositories
Other sheep-dog repositories reference workflows from this repository for:
- Standardized build processes
- Consistent release management
- Automated deployment to GitHub Packages

## Development Environment Setup

### Prerequisites
1. **Eclipse IDE**: Required for Maven plugin development
2. **Java 21**: Consistent across all repositories
3. **Maven**: For build and release management
4. **Docker**: For container operations testing

### Testing the Management Plugin
1. Build the plugin: `mvn clean install`
2. Test with other repositories' release processes
3. Verify GitHub Packages deployment

## Working with Container Operations

### Local Development
Use commands from `cheatsheet.txt` for:
- Setting up local development containers
- Testing Kubernetes deployments
- Managing multi-container environments

### Reference Commands
- **Docker**: Basic container lifecycle management
- **Docker Compose**: Multi-service orchestration
- **Kubernetes**: Production deployment patterns
- **Minikube**: Local Kubernetes testing

## Repository-Specific Notes

### Dependencies
- **Build Order**: Must be built first to provide management plugin for other repositories
- **No External Dependencies**: This repository provides foundational tools
- **Plugin Repository**: Uses GitHub Packages at `maven.pkg.github.com/farhan5248/sheep-dog-ops`

### Release Process
- **Self-Managed**: Uses its own management plugin for releases
- **Version Strategy**: Follows semantic versioning with SNAPSHOT development
- **GitHub Integration**: Automated releases via GitHub Actions

### Operations Focus
- **Infrastructure**: Provides container and deployment guidance
- **Automation**: Standardizes CI/CD across the ecosystem
- **Release Management**: Coordinates version management across repositories

## Integration with Other Repositories

### Downstream Dependencies
All other sheep-dog repositories depend on this repository for:
- **Management Plugin**: Release and version coordination
- **CI/CD Workflows**: Standardized automation patterns
- **Operations Guidance**: Container and deployment standards

### Coordination Responsibilities
- **Version Management**: Ensures consistent versioning across ecosystem
- **Release Orchestration**: Coordinates multi-repository releases
- **Operations Standards**: Maintains infrastructure best practices