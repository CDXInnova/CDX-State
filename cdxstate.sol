// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract PropertyTokenization {

    enum PropertyCategory { CasaCiudad, Lotes, CasaCampo, Departamento, Habitacion, Edificio, GaleriaTienda }

    struct Property {
        address owner;
        uint256 blocks;  // Número de bloques de propiedad (máximo 100)
        string sunarpRecordNFT;  // NFT de la ficha de registro de Sunarp
        string image1;
        string image2;
        string image3;
        PropertyCategory category;  // Categoría de la propiedad
        uint256 rentAmount;  // Monto de alquiler mensual
    }

    struct User {
        uint256 cdxstateBalance;
        mapping(uint256 => uint256) propertyTokens;
        string kycNFT;  // NFT de KYC del usuario
    }
    

    struct Rental {
        uint256 propertyID;
        address tenant;
        uint256 rentAmount;
        uint256 startDate;
        uint256 endDate;
    }

    struct EmergencyPool {
        uint256 totalBalance;
        uint256 lastUsageDate;
        uint256 usageApprovalCount;
        mapping(address => bool) hasVoted;
    }

    mapping(uint256 => Property) public properties;
    mapping(address => User) public users;
    mapping(uint256 => Rental) public rentals;
    mapping(uint256 => EmergencyPool) public emergencyPools;

    address public companyWallet;

    constructor() {
        companyWallet = msg.sender;  // Dirección de la empresa
    }

    event PropertyTokenized(address indexed owner, uint256 indexed propertyID);
    event KYCCreated(address indexed user, string kycNFT);
    event PropertyTokensBought(address indexed buyer, uint256 indexed propertyID, uint256 amount);
    event PropertyTokensSold(address indexed seller, uint256 indexed propertyID, uint256 amount);
    event PropertyRented(address indexed tenant, uint256 indexed propertyID, uint256 startDate, uint256 endDate, uint256 rentAmount);
    event EmergencyPoolFundsUpdated(uint256 indexed propertyID, uint256 totalBalance, uint256 lastUsageDate);
    event PoolUsageApproved(uint256 indexed propertyID, uint256 totalBalance);

    modifier propertyExists(uint256 propertyID) {
        require(properties[propertyID].owner != address(0), "Property not tokenized");
        _;
    }

    modifier propertyNotTokenized(uint256 propertyID) {
        require(properties[propertyID].owner == address(0), "Property already tokenized");
        _;
    }

    modifier sufficientCDXSTATEBalance(uint256 amount) {
        require(users[msg.sender].cdxstateBalance >= amount, "Insufficient CDXSTATE tokens");
        _;
    }
    
    function revertInvalidCategory() internal pure {
        revert("Categoria de propiedad no valida");
    }

    function tokenizeProperty(
        uint256 propertyID,
        string memory sunarpRecordNFT,
        string memory image1,
        string memory image2,
        string memory image3,
        PropertyCategory category
    ) external propertyNotTokenized(propertyID) sufficientCDXSTATEBalance(1) {

        uint256 defaultRent;
        if (category == PropertyCategory.CasaCiudad || category == PropertyCategory.CasaCampo
            || category == PropertyCategory.Departamento || category == PropertyCategory.GaleriaTienda) {
            defaultRent = 450;  // Alquiler mensual predeterminado de 450 USD
        } else if (category == PropertyCategory.Lotes || category == PropertyCategory.Habitacion) {
            defaultRent = 280;  // Alquiler mensual predeterminado de 280 USD
        } else if (category == PropertyCategory.Edificio) {
            defaultRent = 10000;  // Precio mínimo estándar de 10,000 USD
        } else {
            revertInvalidCategory();
        }

        // Crear el token de propiedad
        properties[propertyID] = Property({
            owner: msg.sender,
            blocks: 0,
            sunarpRecordNFT: sunarpRecordNFT,
            image1: image1,
            image2: image2,
            image3: image3,
            category: category,
            rentAmount: defaultRent
        });

        // Transferir tokens CDXSTATE a la empresa
        users[msg.sender].cdxstateBalance -= 1;
        users[companyWallet].cdxstateBalance += 1;

        emit PropertyTokenized(msg.sender, propertyID);
    }

    function buyPropertyTokens(uint256 propertyID, uint256 amount) external propertyExists(propertyID) sufficientCDXSTATEBalance(amount) {
        Property storage property = properties[propertyID];
        require(users[msg.sender].propertyTokens[propertyID] + amount <= 100, "Exceeds maximum property tokens");

        users[msg.sender].propertyTokens[propertyID] += amount;

        // Transferir tokens CDXSTATE del comprador a la empresa
        users[msg.sender].cdxstateBalance -= amount;
        users[companyWallet].cdxstateBalance += amount;

        emit PropertyTokensBought(msg.sender, propertyID, amount);
    }

    function sellPropertyTokens(uint256 propertyID, uint256 amount) external propertyExists(propertyID) {
        Property storage property = properties[propertyID];
        require(users[msg.sender].propertyTokens[propertyID] >= amount, "Insufficient property tokens");

        users[msg.sender].propertyTokens[propertyID] -= amount;

        // Transferir tokens CDXSTATE de la empresa al vendedor
        users[msg.sender].cdxstateBalance += amount;
        users[companyWallet].cdxstateBalance -= amount;

        emit PropertyTokensSold(msg.sender, propertyID, amount);
    }

    function rentProperty(uint256 propertyID, uint256 startDate, uint256 endDate) external propertyExists(propertyID) {
        Property storage property = properties[propertyID];
        require(property.owner == msg.sender, "Only the owner can rent the property");
        require(startDate < endDate, "Invalid rental period");

        // Calculate the rent amount (e.g., based on property value, location, etc.)
        uint256 rentAmount = calculateRentAmount(propertyID, startDate, endDate);

        // Deduct 10% for the emergency pool
        uint256 poolContribution = (rentAmount * 10) / 100;
        rentAmount -= poolContribution;

        // Create a rental record
        rentals[propertyID] = Rental({
            propertyID: propertyID,
            tenant: msg.sender,
            rentAmount: rentAmount,
            startDate: startDate,
            endDate: endDate
        });

        // Add 10% to the emergency pool
        emergencyPools[propertyID].totalBalance += poolContribution;
        updateEmergencyPoolUsageDate(propertyID);

        // Transfer the rent amount to the property owner
        users[msg.sender].cdxstateBalance -= rentAmount;
        users[property.owner].cdxstateBalance += rentAmount;

        emit PropertyRented(msg.sender, propertyID, startDate, endDate, rentAmount);
    }

    function updateEmergencyPoolUsageDate(uint256 propertyID) internal {
        // Update the last usage date of the emergency pool
        emergencyPools[propertyID].lastUsageDate = block.timestamp;
    }

    function approvePoolUsage(uint256 propertyID) external propertyExists(propertyID) {
        EmergencyPool storage pool = emergencyPools[propertyID];
        require(rentals[propertyID].tenant == msg.sender, "Only the tenant can approve pool usage");
        require(!pool.hasVoted[msg.sender], "Already voted");

        // Record the vote
        pool.hasVoted[msg.sender] = true;
        pool.usageApprovalCount++;

        // If 95% of tenants approve, use the pool funds
        if (pool.usageApprovalCount >= ((properties[propertyID].blocks * 95) / 100)) {
            // Distribute the pool funds to property owners (equally)
            uint256 totalBalance = pool.totalBalance;
            uint256 ownersCount = countPropertyOwners(propertyID);
            uint256 distributionAmount = totalBalance / ownersCount;

            for (uint256 i = 1; i <= ownersCount; i++) {
                address owner = getNthPropertyOwner(propertyID, i);
                users[owner].cdxstateBalance += distributionAmount;
            }

            // Reset pool data
            pool.totalBalance = 0;
            pool.usageApprovalCount = 0;
            pool.lastUsageDate = block.timestamp;

            emit PoolUsageApproved(propertyID, totalBalance);
        }

        emit EmergencyPoolFundsUpdated(propertyID, pool.totalBalance, pool.lastUsageDate);
    }

    function countPropertyOwners(uint256 propertyID) internal view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 1; i <= properties[propertyID].blocks; i++) {
            if (properties[propertyID].owner != address(0)) {
                count++;
            }
        }
        return count;
    }

    function getNthPropertyOwner(uint256 propertyID, uint256 n) internal view returns (address) {
        require(n >= 1 && n <= properties[propertyID].blocks, "Invalid owner index");
        for (uint256 i = 1; i <= properties[propertyID].blocks; i++) {
            if (properties[propertyID].owner != address(0)) {
                if (n == i) {
                    return properties[propertyID].owner;
                }
            }
        }
    }

    function calculateRentAmount(uint256 propertyID, uint256 startDate, uint256 endDate) internal pure returns (uint256) {
        // Implement logic to calculate the rent amount
    }

    function changeRentAmount(uint256 propertyID, uint256 newRentAmount) external propertyExists(propertyID) {
        Property storage property = properties[propertyID];
        require(property.owner == msg.sender, "Only the owner can change the rent");
        property.rentAmount = newRentAmount;
    }

    function getKYCNFT(address userAddress) external view returns (string memory) {
        return users[userAddress].kycNFT;
    }
}
