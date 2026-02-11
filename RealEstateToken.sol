// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title RealEstateToken
 * @notice Contrato para la tokenización fraccionada de propiedades inmobiliarias.
 *         Cada propertyId representa un inmueble distinto.
 *         Las fracciones son fungibles dentro de la misma propiedad.
 * @dev    Basado en OpenZeppelin ERC-1155 v5. Diseñado para Polygon.
 *         Incluye: whitelist, pausable, burnable, supply tracking,
 *         venta directa, dividendos y gestión de múltiples propiedades.
 */
contract RealEstateToken is ERC1155, ERC1155Burnable, ERC1155Supply, Ownable, Pausable {
    using Strings for uint256;

    // ─────────────────────────────────────────────
    //  INFORMACIÓN DE PROPIEDADES
    // ─────────────────────────────────────────────

    struct Property {
        string  name;              // Ej: "Casa Mérida #1"
        string  location;          // Dirección física o coordenadas
        string  propertyType;      // Tipo: casa, apartamento, local, terreno
        uint256 areaSqMeters;      // Superficie en metros cuadrados
        uint256 totalFractions;    // Total de fracciones emitidas
        uint256 pricePerFraction;  // Precio por fracción en wei (POL)
        uint256 appraisalValueUSD; // Valor de tasación en USD (sin decimales)
        string  cadastralId;       // Identificador catastral / registro
        string  legalDocHash;      // Hash IPFS del documento legal (escritura)
        string  metadataURI;       // URI IPFS con fotos, planos, documentos
        bool    saleActive;        // Si la venta de fracciones está abierta
        bool    exists;            // Si la propiedad fue registrada
    }

    uint256 public nextPropertyId;
    mapping(uint256 => Property) public properties;

    // ─────────────────────────────────────────────
    //  CONTROL DE INVERSORES (WHITELIST)
    // ─────────────────────────────────────────────

    bool public whitelistEnabled;
    mapping(address => bool) public whitelisted;

    // ─────────────────────────────────────────────
    //  DIVIDENDOS / RENTAS
    // ─────────────────────────────────────────────

    mapping(uint256 => uint256) public totalDividendsDistributed; // por propiedad

    // ─────────────────────────────────────────────
    //  EVENTOS
    // ─────────────────────────────────────────────

    event PropertyTokenized(
        uint256 indexed propertyId,
        string name,
        string location,
        uint256 totalFractions,
        uint256 appraisalValueUSD
    );
    event PropertyUpdated(uint256 indexed propertyId, string field);
    event AppraisalUpdated(uint256 indexed propertyId, uint256 oldValue, uint256 newValue);
    event SaleStatusChanged(uint256 indexed propertyId, bool active);
    event PriceUpdated(uint256 indexed propertyId, uint256 oldPrice, uint256 newPrice);
    event FractionsPurchased(
        uint256 indexed propertyId,
        address indexed buyer,
        uint256 amount,
        uint256 totalPaid
    );
    event WhitelistUpdated(address indexed account, bool status);
    event WhitelistToggled(bool enabled);
    event DividendsDistributed(uint256 indexed propertyId, uint256 totalAmount, uint256 holdersCount);
    event FundsWithdrawn(address indexed to, uint256 amount);

    // ─────────────────────────────────────────────
    //  CONSTRUCTOR
    // ─────────────────────────────────────────────

    /**
     * @notice Despliega el contrato. No crea ninguna propiedad aún.
     * @dev    Las propiedades se añaden después con tokenizeProperty().
     */
    constructor() ERC1155("") Ownable(msg.sender) {
        whitelisted[msg.sender] = true;
        whitelistEnabled = false; // Desactivada para pruebas
    }

    // ─────────────────────────────────────────────
    //  TOKENIZACIÓN DE PROPIEDADES
    // ─────────────────────────────────────────────

    /**
     * @notice Tokeniza una nueva propiedad creando todas sus fracciones.
     * @dev    Todas las fracciones se acuñan al owner (SPV).
     * @param _name             Nombre descriptivo del inmueble
     * @param _location         Dirección física o coordenadas GPS
     * @param _propertyType     Tipo: "casa", "apartamento", "local", "terreno"
     * @param _areaSqMeters     Superficie en m²
     * @param _totalFractions   Número total de fracciones a emitir
     * @param _pricePerFraction Precio inicial por fracción en wei (0 para pruebas)
     * @param _appraisalValueUSD Valor de tasación en USD
     * @param _cadastralId      Número catastral o de registro público
     * @param _legalDocHash     Hash IPFS del documento de propiedad
     * @param _metadataURI      URI IPFS con fotos, planos y documentos
     */
    function tokenizeProperty(
        string memory _name,
        string memory _location,
        string memory _propertyType,
        uint256 _areaSqMeters,
        uint256 _totalFractions,
        uint256 _pricePerFraction,
        uint256 _appraisalValueUSD,
        string memory _cadastralId,
        string memory _legalDocHash,
        string memory _metadataURI
    ) external onlyOwner {
        uint256 propertyId = nextPropertyId;

        properties[propertyId] = Property({
            name: _name,
            location: _location,
            propertyType: _propertyType,
            areaSqMeters: _areaSqMeters,
            totalFractions: _totalFractions,
            pricePerFraction: _pricePerFraction,
            appraisalValueUSD: _appraisalValueUSD,
            cadastralId: _cadastralId,
            legalDocHash: _legalDocHash,
            metadataURI: _metadataURI,
            saleActive: false,
            exists: true
        });

        // Mintear TODAS las fracciones al owner (SPV)
        _mint(msg.sender, propertyId, _totalFractions, "");

        emit PropertyTokenized(
            propertyId,
            _name,
            _location,
            _totalFractions,
            _appraisalValueUSD
        );

        nextPropertyId++;
    }

    // ─────────────────────────────────────────────
    //  CONSULTA DE PROPIEDADES
    // ─────────────────────────────────────────────

    /**
     * @notice Retorna toda la información de una propiedad.
     */
    function getProperty(uint256 _propertyId) external view returns (Property memory) {
        require(properties[_propertyId].exists, "Propiedad no existe");
        return properties[_propertyId];
    }

    /**
     * @notice Retorna la cantidad total de propiedades registradas.
     */
    function totalProperties() external view returns (uint256) {
        return nextPropertyId;
    }

    // ─────────────────────────────────────────────
    //  ACTUALIZACIÓN DE PROPIEDADES
    // ─────────────────────────────────────────────

    /**
     * @notice Actualiza el valor de tasación de una propiedad.
     */
    function updateAppraisal(uint256 _propertyId, uint256 _newValue) external onlyOwner {
        require(properties[_propertyId].exists, "Propiedad no existe");
        uint256 oldValue = properties[_propertyId].appraisalValueUSD;
        properties[_propertyId].appraisalValueUSD = _newValue;
        emit AppraisalUpdated(_propertyId, oldValue, _newValue);
    }

    /**
     * @notice Actualiza el hash del documento legal (ej: nueva escritura).
     */
    function updateLegalDocHash(uint256 _propertyId, string memory _newHash) external onlyOwner {
        require(properties[_propertyId].exists, "Propiedad no existe");
        properties[_propertyId].legalDocHash = _newHash;
        emit PropertyUpdated(_propertyId, "legalDocHash");
    }

    /**
     * @notice Actualiza la URI de metadata (fotos, planos, etc.).
     */
    function updateMetadataURI(uint256 _propertyId, string memory _newURI) external onlyOwner {
        require(properties[_propertyId].exists, "Propiedad no existe");
        properties[_propertyId].metadataURI = _newURI;
        emit PropertyUpdated(_propertyId, "metadataURI");
    }

    /**
     * @notice Actualiza la ubicación (si hay corrección o dato GPS).
     */
    function updateLocation(uint256 _propertyId, string memory _newLocation) external onlyOwner {
        require(properties[_propertyId].exists, "Propiedad no existe");
        properties[_propertyId].location = _newLocation;
        emit PropertyUpdated(_propertyId, "location");
    }

    /**
     * @notice Actualiza el identificador catastral.
     */
    function updateCadastralId(uint256 _propertyId, string memory _newId) external onlyOwner {
        require(properties[_propertyId].exists, "Propiedad no existe");
        properties[_propertyId].cadastralId = _newId;
        emit PropertyUpdated(_propertyId, "cadastralId");
    }

    // ─────────────────────────────────────────────
    //  WHITELIST (CONTROL DE INVERSORES)
    // ─────────────────────────────────────────────

    /**
     * @notice Activa o desactiva la verificación de whitelist global.
     */
    function toggleWhitelist(bool _enabled) external onlyOwner {
        whitelistEnabled = _enabled;
        emit WhitelistToggled(_enabled);
    }

    /**
     * @notice Agrega o remueve una dirección de la whitelist.
     */
    function setWhitelist(address _account, bool _status) external onlyOwner {
        whitelisted[_account] = _status;
        emit WhitelistUpdated(_account, _status);
    }

    /**
     * @notice Agrega o remueve múltiples direcciones de una vez.
     */
    function batchWhitelist(address[] calldata _accounts, bool _status) external onlyOwner {
        for (uint256 i = 0; i < _accounts.length; i++) {
            whitelisted[_accounts[i]] = _status;
            emit WhitelistUpdated(_accounts[i], _status);
        }
    }

    // ─────────────────────────────────────────────
    //  VENTA DE FRACCIONES
    // ─────────────────────────────────────────────

    /**
     * @notice Activa o desactiva la venta de una propiedad específica.
     */
    function setSaleStatus(uint256 _propertyId, bool _active) external onlyOwner {
        require(properties[_propertyId].exists, "Propiedad no existe");
        properties[_propertyId].saleActive = _active;
        emit SaleStatusChanged(_propertyId, _active);
    }

    /**
     * @notice Actualiza el precio por fracción de una propiedad.
     */
    function setPrice(uint256 _propertyId, uint256 _newPrice) external onlyOwner {
        require(properties[_propertyId].exists, "Propiedad no existe");
        uint256 oldPrice = properties[_propertyId].pricePerFraction;
        properties[_propertyId].pricePerFraction = _newPrice;
        emit PriceUpdated(_propertyId, oldPrice, _newPrice);
    }

    /**
     * @notice Permite a un usuario comprar fracciones de una propiedad enviando POL.
     * @param _propertyId ID de la propiedad
     * @param _amount     Cantidad de fracciones a comprar
     */
    function buyFractions(uint256 _propertyId, uint256 _amount) external payable whenNotPaused {
        Property memory prop = properties[_propertyId];
        require(prop.exists, "Propiedad no existe");
        require(prop.saleActive, "Venta no activa para esta propiedad");
        require(_amount > 0, "Cantidad debe ser mayor a 0");

        uint256 cost = prop.pricePerFraction * _amount;
        require(msg.value >= cost, "POL insuficiente enviado");

        require(
            balanceOf(owner(), _propertyId) >= _amount,
            "No hay suficientes fracciones disponibles"
        );

        // Transferir fracciones del owner al comprador
        _safeTransferFrom(owner(), msg.sender, _propertyId, _amount, "");

        // Devolver cambio si envió de más
        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }

        emit FractionsPurchased(_propertyId, msg.sender, _amount, cost);
    }

    // ─────────────────────────────────────────────
    //  DISTRIBUCIÓN DE DIVIDENDOS / RENTAS
    // ─────────────────────────────────────────────

    /**
     * @notice Distribuye POL proporcionalmente entre holders de una propiedad.
     * @dev    Ejemplo: si la propiedad genera renta, la SPV la distribuye aquí.
     * @param _propertyId ID de la propiedad cuyos dividendos se distribuyen
     * @param _holders    Lista de direcciones que recibirán dividendos
     */
    function distributeDividends(
        uint256 _propertyId,
        address[] calldata _holders
    ) external payable onlyOwner {
        require(properties[_propertyId].exists, "Propiedad no existe");
        require(msg.value > 0, "Debe enviar POL para distribuir");
        require(_holders.length > 0, "Lista de holders vacia");

        uint256 propTotalSupply = properties[_propertyId].totalFractions;
        uint256 totalDistributed = 0;

        for (uint256 i = 0; i < _holders.length; i++) {
            uint256 holderBalance = balanceOf(_holders[i], _propertyId);
            if (holderBalance > 0) {
                uint256 share = (msg.value * holderBalance) / propTotalSupply;
                if (share > 0) {
                    payable(_holders[i]).transfer(share);
                    totalDistributed += share;
                }
            }
        }

        totalDividendsDistributed[_propertyId] += totalDistributed;
        emit DividendsDistributed(_propertyId, totalDistributed, _holders.length);
    }

    // ─────────────────────────────────────────────
    //  PAUSA DE EMERGENCIA
    // ─────────────────────────────────────────────

    /**
     * @notice Pausa TODAS las transferencias y ventas. Solo para emergencias.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Reanuda las operaciones después de una pausa.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ─────────────────────────────────────────────
    //  RETIRO DE FONDOS
    // ─────────────────────────────────────────────

    /**
     * @notice Retira los fondos (POL) acumulados en el contrato al owner.
     */
    function withdrawFunds() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No hay fondos para retirar");
        payable(owner()).transfer(balance);
        emit FundsWithdrawn(owner(), balance);
    }

    // ─────────────────────────────────────────────
    //  UTILIDADES DE CONSULTA
    // ─────────────────────────────────────────────

    /**
     * @notice Calcula el porcentaje de propiedad de un holder sobre un inmueble.
     * @return Porcentaje con 2 decimales (ej: 2500 = 25.00%)
     */
    function ownershipPercentage(
        address _account,
        uint256 _propertyId
    ) external view returns (uint256) {
        require(properties[_propertyId].exists, "Propiedad no existe");
        uint256 propTotalSupply = properties[_propertyId].totalFractions;
        if (propTotalSupply == 0) return 0;
        return (balanceOf(_account, _propertyId) * 10000) / propTotalSupply;
    }

    /**
     * @notice Calcula el valor en USD de las fracciones de un holder.
     * @return Valor proporcional basado en la tasación del inmueble.
     */
    function fractionValueUSD(
        address _account,
        uint256 _propertyId
    ) external view returns (uint256) {
        require(properties[_propertyId].exists, "Propiedad no existe");
        uint256 propTotalSupply = properties[_propertyId].totalFractions;
        if (propTotalSupply == 0) return 0;
        return (balanceOf(_account, _propertyId) * properties[_propertyId].appraisalValueUSD) / propTotalSupply;
    }

    /**
     * @notice Retorna cuántas fracciones aún tiene la SPV disponibles para venta.
     */
    function availableFractions(uint256 _propertyId) external view returns (uint256) {
        require(properties[_propertyId].exists, "Propiedad no existe");
        return balanceOf(owner(), _propertyId);
    }

    // ─────────────────────────────────────────────
    //  METADATA URI POR PROPIEDAD
    // ─────────────────────────────────────────────

    /**
     * @notice Override: retorna la URI de metadata específica de cada propiedad.
     */
    function uri(uint256 _tokenId) public view override returns (string memory) {
        require(properties[_tokenId].exists, "Token no existe");
        return properties[_tokenId].metadataURI;
    }

    // ─────────────────────────────────────────────
    //  OVERRIDES REQUERIDOS
    // ─────────────────────────────────────────────

    /**
     * @dev Intercepta cada transferencia para verificar:
     *      1. Que el contrato no esté en pausa.
     *      2. Que el destinatario esté en la whitelist (si está activa).
     *      Combina los overrides de ERC1155Supply y Pausable.
     */
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override(ERC1155, ERC1155Supply) whenNotPaused {
        // Verificar whitelist si está activada (excepto para burn)
        if (whitelistEnabled && to != address(0)) {
            require(whitelisted[to], "Destinatario no esta en la whitelist");
        }
        super._update(from, to, ids, values);
    }

    // ─────────────────────────────────────────────
    //  RECEPCIÓN DE POL
    // ─────────────────────────────────────────────

    /**
     * @notice Recibe POL directamente (para dividendos u otros pagos).
     */
    receive() external payable {}
}
