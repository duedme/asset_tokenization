// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title ArtFractionToken
 * @notice Contrato para la tokenización fraccionada de una obra de arte física.
 *         Cada token representa una fracción de la propiedad de la pintura.
 * @dev    Basado en OpenZeppelin ERC-20 v5. Diseñado para Polygon.
 */
contract ArtFractionToken is ERC20, ERC20Burnable, Ownable, Pausable {

    // ─────────────────────────────────────────────
    //  INFORMACIÓN DE LA OBRA DE ARTE
    // ─────────────────────────────────────────────

    struct ArtworkInfo {
        string  title;            // Nombre de la obra
        string  artist;           // Nombre del artista
        uint256 year;             // Año de creación
        string  medium;           // Técnica (óleo, acrílico, etc.)
        string  dimensions;       // Dimensiones físicas
        uint256 appraisalValue;   // Valor de tasación en USD (sin decimales)
        string  metadataURI;      // URI a metadata completa en IPFS
        string  physicalLocation; // Ubicación de custodia de la obra
    }

    ArtworkInfo public artwork;

    // ─────────────────────────────────────────────
    //  CONTROL DE INVERSORES (WHITELIST)
    // ─────────────────────────────────────────────

    bool public whitelistEnabled;
    mapping(address => bool) public whitelisted;

    // ─────────────────────────────────────────────
    //  CONTROL DE VENTAS
    // ─────────────────────────────────────────────

    bool   public saleActive;
    uint256 public pricePerToken;  // Precio por token en wei (POL/MATIC)

    // ─────────────────────────────────────────────
    //  DIVIDENDOS / DISTRIBUCIÓN DE GANANCIAS
    // ─────────────────────────────────────────────

    uint256 public totalDividendsDistributed;

    // ─────────────────────────────────────────────
    //  EVENTOS
    // ─────────────────────────────────────────────

    event ArtworkRegistered(string title, string artist, uint256 appraisalValue);
    event ArtworkInfoUpdated(string field, string newValue);
    event AppraisalUpdated(uint256 oldValue, uint256 newValue);
    event WhitelistUpdated(address indexed account, bool status);
    event WhitelistToggled(bool enabled);
    event SaleStatusChanged(bool active);
    event PriceUpdated(uint256 oldPrice, uint256 newPrice);
    event TokensPurchased(address indexed buyer, uint256 amount, uint256 totalPaid);
    event DividendsDistributed(uint256 totalAmount, uint256 holders);
    event FundsWithdrawn(address indexed to, uint256 amount);

    // ─────────────────────────────────────────────
    //  CONSTRUCTOR
    // ─────────────────────────────────────────────

    /**
     * @notice Despliega el contrato y registra la obra de arte.
     * @param _name         Nombre del token (ej: "MiPintura Token")
     * @param _symbol       Símbolo del token (ej: "MPNT")
     * @param _totalSupply  Cantidad total de fracciones (ej: 10000)
     * @param _title        Título de la obra de arte
     * @param _artist       Nombre del artista
     * @param _year         Año de creación de la obra
     * @param _medium       Técnica utilizada
     * @param _dimensions   Dimensiones de la obra
     * @param _appraisalValue Valor de tasación en USD
     * @param _metadataURI  Enlace IPFS con imagen HD y documentos
     * @param _physicalLocation Lugar de custodia de la obra
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        string memory _title,
        string memory _artist,
        uint256 _year,
        string memory _medium,
        string memory _dimensions,
        uint256 _appraisalValue,
        string memory _metadataURI,
        string memory _physicalLocation
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        // Acuñar TODOS los tokens al deployer (la SPV)
        _mint(msg.sender, _totalSupply * (10 ** decimals()));

        // Registrar la información de la obra
        artwork = ArtworkInfo({
            title: _title,
            artist: _artist,
            year: _year,
            medium: _medium,
            dimensions: _dimensions,
            appraisalValue: _appraisalValue,
            metadataURI: _metadataURI,
            physicalLocation: _physicalLocation
        });

        // El owner (SPV) siempre está en la whitelist
        whitelisted[msg.sender] = true;
        whitelistEnabled = false; // Deshabilitada por defecto para pruebas

        emit ArtworkRegistered(_title, _artist, _appraisalValue);
    }

    // ─────────────────────────────────────────────
    //  FUNCIONES DE INFORMACIÓN DE LA OBRA
    // ─────────────────────────────────────────────

    /**
     * @notice Retorna toda la información de la obra en una sola llamada.
     */
    function getArtworkInfo() external view returns (
        string memory title,
        string memory artist,
        uint256 year,
        string memory medium,
        string memory dimensions,
        uint256 appraisalValue,
        string memory metadataURI,
        string memory physicalLocation
    ) {
        return (
            artwork.title,
            artwork.artist,
            artwork.year,
            artwork.medium,
            artwork.dimensions,
            artwork.appraisalValue,
            artwork.metadataURI,
            artwork.physicalLocation
        );
    }

    /**
     * @notice Actualiza el valor de tasación de la obra.
     * @dev    Solo el owner (SPV) puede llamar esta función.
     */
    function updateAppraisal(uint256 _newValue) external onlyOwner {
        uint256 oldValue = artwork.appraisalValue;
        artwork.appraisalValue = _newValue;
        emit AppraisalUpdated(oldValue, _newValue);
    }

    /**
     * @notice Actualiza el URI de metadata (ej: nueva imagen, nuevo certificado).
     */
    function updateMetadataURI(string memory _newURI) external onlyOwner {
        artwork.metadataURI = _newURI;
        emit ArtworkInfoUpdated("metadataURI", _newURI);
    }

    /**
     * @notice Actualiza la ubicación física de custodia.
     */
    function updatePhysicalLocation(string memory _newLocation) external onlyOwner {
        artwork.physicalLocation = _newLocation;
        emit ArtworkInfoUpdated("physicalLocation", _newLocation);
    }

    // ─────────────────────────────────────────────
    //  WHITELIST (LISTA DE INVERSORES AUTORIZADOS)
    // ─────────────────────────────────────────────

    /**
     * @notice Activa o desactiva la verificación de whitelist.
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
     * @notice Agrega múltiples direcciones a la whitelist de una vez.
     */
    function batchWhitelist(address[] calldata _accounts, bool _status) external onlyOwner {
        for (uint256 i = 0; i < _accounts.length; i++) {
            whitelisted[_accounts[i]] = _status;
            emit WhitelistUpdated(_accounts[i], _status);
        }
    }

    // ─────────────────────────────────────────────
    //  VENTA DE TOKENS
    // ─────────────────────────────────────────────

    /**
     * @notice Activa o desactiva la venta de tokens.
     */
    function setSaleStatus(bool _active) external onlyOwner {
        saleActive = _active;
        emit SaleStatusChanged(_active);
    }

    /**
     * @notice Establece el precio por token en wei.
     * @param _price Precio en wei por cada token (1 token = 10^decimals unidades)
     */
    function setPrice(uint256 _price) external onlyOwner {
        uint256 oldPrice = pricePerToken;
        pricePerToken = _price;
        emit PriceUpdated(oldPrice, _price);
    }

    /**
     * @notice Permite a un usuario comprar tokens enviando POL/MATIC.
     * @param _amount Cantidad de tokens a comprar (sin decimales; se ajusta internamente)
     */
    function buyTokens(uint256 _amount) external payable whenNotPaused {
        require(saleActive, "La venta no esta activa");
        require(_amount > 0, "Cantidad debe ser mayor a 0");

        uint256 cost = _amount * pricePerToken;
        require(msg.value >= cost, "POL insuficiente enviado");

        uint256 tokenAmount = _amount * (10 ** decimals());
        require(balanceOf(owner()) >= tokenAmount, "No hay suficientes tokens disponibles");

        // Transferir tokens desde el owner al comprador
        _transfer(owner(), msg.sender, tokenAmount);

        // Devolver cambio si envió de más
        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }

        emit TokensPurchased(msg.sender, _amount, cost);
    }

    // ─────────────────────────────────────────────
    //  DISTRIBUCIÓN DE DIVIDENDOS
    // ─────────────────────────────────────────────

    /**
     * @notice Distribuye POL proporcionalmente a una lista de holders.
     * @dev    El owner envía POL al contrato y se reparte según % de tokens.
     * @param _holders Lista de direcciones que recibirán dividendos.
     */
    function distributeDividends(address[] calldata _holders) external payable onlyOwner {
        require(msg.value > 0, "Debe enviar POL para distribuir");
        require(_holders.length > 0, "Lista de holders vacia");

        uint256 totalDistributed = 0;

        for (uint256 i = 0; i < _holders.length; i++) {
            uint256 holderBalance = balanceOf(_holders[i]);
            if (holderBalance > 0) {
                // Proporción = (balance del holder / supply total) * monto total
                uint256 share = (msg.value * holderBalance) / totalSupply();
                if (share > 0) {
                    payable(_holders[i]).transfer(share);
                    totalDistributed += share;
                }
            }
        }

        totalDividendsDistributed += totalDistributed;
        emit DividendsDistributed(totalDistributed, _holders.length);
    }

    // ─────────────────────────────────────────────
    //  PAUSA DE EMERGENCIA
    // ─────────────────────────────────────────────

    /**
     * @notice Pausa todas las transferencias y ventas. Solo emergencias.
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
     * @notice Retira los fondos (POL) acumulados por ventas al owner.
     */
    function withdrawFunds() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No hay fondos para retirar");
        payable(owner()).transfer(balance);
        emit FundsWithdrawn(owner(), balance);
    }

    // ─────────────────────────────────────────────
    //  OVERRIDES REQUERIDOS
    // ─────────────────────────────────────────────

    /**
     * @dev Intercepta cada transferencia para verificar:
     *      1. Que el contrato no esté en pausa.
     *      2. Que el destinatario esté en la whitelist (si está activa).
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override whenNotPaused {
        // Verificar whitelist si está activada (excepto para mint/burn)
        if (whitelistEnabled && to != address(0)) {
            require(whitelisted[to], "Destinatario no esta en la whitelist");
        }
        super._update(from, to, value);
    }

    // ─────────────────────────────────────────────
    //  UTILIDADES
    // ─────────────────────────────────────────────

    /**
     * @notice Calcula qué porcentaje de la obra posee una dirección.
     * @return Porcentaje con 2 decimales (ej: 2500 = 25.00%)
     */
    function ownershipPercentage(address _account) external view returns (uint256) {
        if (totalSupply() == 0) return 0;
        return (balanceOf(_account) * 10000) / totalSupply();
    }

    /**
     * @notice Calcula el valor en USD de los tokens de una dirección.
     * @return Valor proporcional basado en la tasación de la obra.
     */
    function tokenValueUSD(address _account) external view returns (uint256) {
        if (totalSupply() == 0) return 0;
        return (balanceOf(_account) * artwork.appraisalValue) / totalSupply();
    }

    /**
     * @notice Recibe POL directamente (para dividendos u otros pagos).
     */
    receive() external payable {}
}
