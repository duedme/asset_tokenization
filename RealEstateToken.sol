// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title RealEstateToken
 * @dev Contrato para tokenizar una propiedad inmobiliaria en fracciones.
 *      Cada tokenId representa una propiedad distinta.
 *      Las fracciones son fungibles dentro de la misma propiedad.
 */
contract RealEstateToken is ERC1155, Ownable {
    using Strings for uint256;

    struct Property {
        string name;            // Ej: "Casa Caracas #1"
        string location;        // Dirección o coordenadas
        uint256 totalSupply;    // Total de fracciones emitidas
        uint256 pricePerToken;  // Precio por fracción en wei
        string legalDocHash;    // Hash IPFS del documento legal (escritura)
        string metadataURI;     // URI de metadata en IPFS
        bool exists;
    }
    checar que si baja mucho el token que no puedan vender los usuarios

    uint256 public nextPropertyId;
    mapping(uint256 => Property) public properties;

    event PropertyTokenized(
        uint256 indexed propertyId,
        string name,
        uint256 totalFractions,
        uint256 pricePerToken
    );
    event FractionsPurchased(
        uint256 indexed propertyId,
        address indexed buyer,
        uint256 amount
    );

    constructor() ERC1155("") Ownable(msg.sender) {}

    /// @notice Tokeniza una nueva propiedad creando fracciones
    /// @param _name Nombre descriptivo de la propiedad
    /// @param _location Dirección física o coordenadas
    /// @param _totalFractions Número total de fracciones a emitir
    /// @param _pricePerToken Precio por fracción en wei (0 para pruebas)
    /// @param _legalDocHash Hash IPFS del documento de propiedad
    /// @param _metadataURI URI de metadata IPFS con info de la propiedad
    function tokenizeProperty(
        string memory _name,
        string memory _location,
        uint256 _totalFractions,
        uint256 _pricePerToken,
        string memory _legalDocHash,
        string memory _metadataURI
    ) external onlyOwner {
        uint256 propertyId = nextPropertyId;

        properties[propertyId] = Property({
            name: _name,
            location: _location,
            totalSupply: _totalFractions,
            pricePerToken: _pricePerToken,
            legalDocHash: _legalDocHash,
            metadataURI: _metadataURI,
            exists: true
        });

        // Mintear todas las fracciones al owner (SPV)
        _mint(msg.sender, propertyId, _totalFractions, "");

        emit PropertyTokenized(propertyId, _name, _totalFractions, _pricePerToken);
        nextPropertyId++;
    }

    /// @notice Comprar fracciones de una propiedad (para cuando activen ventas)
    function buyFractions(uint256 _propertyId, uint256 _amount) external payable {
        Property memory prop = properties[_propertyId];
        require(prop.exists, "Propiedad no existe");
        require(
            msg.value >= prop.pricePerToken * _amount,
            "Pago insuficiente"
        );
        require(
            balanceOf(owner(), _propertyId) >= _amount,
            "No hay suficientes fracciones disponibles"
        );

        // Transferir fracciones del owner al comprador
        _safeTransferFrom(owner(), msg.sender, _propertyId, _amount, "");

        emit FractionsPurchased(_propertyId, msg.sender, _amount);
    }

    /// @notice Consultar info de una propiedad
    function getProperty(uint256 _propertyId) external view returns (Property memory) {
        require(properties[_propertyId].exists, "Propiedad no existe");
        return properties[_propertyId];
    }

    /// @notice Override URI para metadata por propiedad
    function uri(uint256 _tokenId) public view override returns (string memory) {
        require(properties[_tokenId].exists, "Token no existe");
        return properties[_tokenId].metadataURI;
    }

    /// @notice Retirar fondos del contrato (solo owner/SPV)
    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
}
