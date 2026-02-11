# 🎨 ArtFractionToken — Tokenización Fraccionada de Obra de Arte

## Documento Técnico y de Negocio para Stakeholders

**Versión:** 1.0  
**Fecha:** Febrero 2026  
**Blockchain:** Polygon (Amoy Testnet para pruebas / Polygon Mainnet para producción)  
**Estándar:** ERC-20 (Fracciones fungibles de una obra de arte)

---

## 1. Resumen Ejecutivo

Este documento describe el smart contract `ArtFractionToken`, diseñado para representar la **propiedad fraccionada de una pintura física** como tokens digitales sobre la blockchain de Polygon. Cada token equivale a una fracción porcentual de la obra, permitiendo que múltiples personas posean partes de una pieza de arte sin necesidad de intermediarios tradicionales.

### Problema vs. Solución

| Problema Tradicional | Solución con Tokenización |
|---|---|
| Una pintura valiosa solo puede tener 1 dueño | Múltiples personas pueden poseer fracciones |
| Vender una parte de una obra es legalmente complejo | Transferencia instantánea en blockchain |
| Se necesitan galerías, notarios, intermediarios | Transacción directa entre comprador y vendedor |
| Difícil probar la autenticidad y trazabilidad | Registro inmutable en blockchain |
| Liquidez nula: o vendes todo o nada | Mercado secundario 24/7 para fracciones |
| Procesos lentos (semanas/meses) | Transacciones en segundos |

---

## 2. Arquitectura General

```
┌─────────────────────────────────────────────────────────────────┐
│                    MUNDO FÍSICO                                 │
│                                                                 │
│   ┌──────────────┐     ┌──────────────────────────────────┐    │
│   │   Pintura     │     │  SPV / Entidad Legal Propietaria │    │
│   │   Original    │────▶│  (Posee el título de la obra)    │    │
│   │   (Custodia)  │     │  Emite tokens como representación│    │
│   └──────────────┘     └──────────────┬───────────────────┘    │
│                                        │                        │
└────────────────────────────────────────┼────────────────────────┘
                                         │
                    ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┼ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
                                         │
┌────────────────────────────────────────┼────────────────────────┐
│                 BLOCKCHAIN (Polygon)   │                        │
│                                        ▼                        │
│              ┌───────────────────────────────┐                  │
│              │    ArtFractionToken (ERC-20)   │                  │
│              │    ─────────────────────────   │                  │
│              │  • Nombre: "MiPintura Token"   │                  │
│              │  • Símbolo: "MPNT"             │                  │
│              │  • Supply: 10,000 tokens       │                  │
│              │  • 1 token = 0.01% de la obra  │                  │
│              │  • Metadata IPFS (imagen HD)   │                  │
│              └──────────┬────────────────────┘                  │
│                         │                                       │
│            ┌────────────┼─────────────┐                         │
│            ▼            ▼             ▼                          │
│     ┌──────────┐ ┌──────────┐ ┌──────────┐                     │
│     │Inversor A│ │Inversor B│ │Inversor C│                      │
│     │ 2,500 tk │ │ 5,000 tk │ │ 2,500 tk │                      │
│     │  (25%)   │ │  (50%)   │ │  (25%)   │                      │
│     └──────────┘ └──────────┘ └──────────┘                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. ¿Por qué ERC-20 y no ERC-721 (NFT)?

| Característica | ERC-721 (NFT) | ERC-20 (Fungible) |
|---|---|---|
| **Divisibilidad** | ❌ No divisible (1 token = 1 pieza entera) | ✅ Divisible en miles/millones de fracciones |
| **Caso de uso** | Propiedad única (1 dueño) | Propiedad compartida (muchos dueños) |
| **Liquidez** | Baja (hay que vender el NFT completo) | Alta (se venden fracciones individuales) |
| **Compatibilidad con DEX** | ❌ No se comercia en exchanges | ✅ Compatible con Uniswap, QuickSwap, etc. |
| **Ideal para** | Arte digital único | Inversión fraccionada en arte físico |

**Decisión:** Usamos **ERC-20** porque el objetivo es vender **partes** de la pintura, no la pintura como unidad indivisible.

---

## 4. Código del Smart Contract

```solidity
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
```

---

## 5. Explicación Función por Función

### 5.1 Constructor — Registro Inicial de la Obra

```
constructor(_name, _symbol, _totalSupply, _title, _artist, ...)
```

**¿Qué hace?** Es lo que se ejecuta **una sola vez** cuando se despliega el contrato. Registra toda la información de la pintura en la blockchain y crea todos los tokens.

**Ejemplo concreto:** Si creamos 10,000 tokens para una pintura valorada en $50,000 USD:
- Se crean 10,000 tokens (con 18 decimales internamente)
- Todos los tokens van a la billetera de la SPV (quien despliega)
- 1 token = 0.01% de la pintura = $5.00 USD

---

### 5.2 Información de la Obra

| Función | ¿Qué hace? | ¿Quién puede usarla? |
|---|---|---|
| `getArtworkInfo()` | Muestra todos los datos de la pintura | Cualquiera (lectura pública) |
| `updateAppraisal()` | Cambia el valor de tasación | Solo el owner (SPV) |
| `updateMetadataURI()` | Actualiza el enlace a la imagen/docs en IPFS | Solo el owner (SPV) |
| `updatePhysicalLocation()` | Cambia la ubicación de custodia | Solo el owner (SPV) |

**¿Por qué importa?** Si la pintura es retasada por un perito (ej: de $50,000 a $75,000), se actualiza en la blockchain y automáticamente `tokenValueUSD()` reflejará el nuevo valor para cada holder.

---

### 5.3 Whitelist — Control de Inversores

| Función | ¿Qué hace? |
|---|---|
| `toggleWhitelist(true/false)` | Activa o desactiva la verificación |
| `setWhitelist(dirección, true/false)` | Agrega o remueve un inversor |
| `batchWhitelist([dir1, dir2, ...], true)` | Agrega múltiples inversores de una vez |

**¿Para qué sirve?** Cuando la whitelist está **activada**, solo las billeteras autorizadas pueden recibir tokens. Esto es fundamental para cumplimiento regulatorio (KYC/AML). En modo prueba, viene **desactivada** para facilitar las pruebas.

---

### 5.4 Venta de Tokens

| Función | ¿Qué hace? |
|---|---|
| `setSaleStatus(true/false)` | Abre o cierra la venta |
| `setPrice(precio_en_wei)` | Establece cuánto cuesta cada token en POL |
| `buyTokens(cantidad)` | El comprador envía POL y recibe tokens |

**Flujo de compra:**
```
Comprador envía 10 POL ──▶ Contrato verifica precio ──▶ Transfiere tokens ──▶ Devuelve cambio
```

**Ejemplo:** Si el precio es 0.5 POL por token y alguien llama `buyTokens(20)`:
- Debe enviar 10 POL (20 × 0.5)
- Recibe 20 tokens (= 0.20% de la pintura)
- Si envió 12 POL, recibe 2 POL de vuelta

---

### 5.5 Distribución de Dividendos

```
distributeDividends([holder1, holder2, holder3])
```

**¿Qué hace?** Si la obra genera ingresos (ej: una exhibición cobra entrada, una licencia de imagen, o se vende un print), el owner puede **repartir las ganancias** proporcionalmente entre los holders.

**Ejemplo:** La pintura genera $1,000 en una exhibición. Se envía el equivalente en POL:
- Holder A (50% de tokens) → recibe $500 en POL
- Holder B (30% de tokens) → recibe $300 en POL
- Holder C (20% de tokens) → recibe $200 en POL

---

### 5.6 Seguridad y Control

| Función | ¿Qué hace? | Cuándo usarla |
|---|---|---|
| `pause()` | Congela TODAS las transferencias y ventas | Emergencia, hackeo detectado, orden legal |
| `unpause()` | Reanuda operaciones normales | Cuando se resuelve la emergencia |
| `withdrawFunds()` | Retira POL acumulado por ventas | Cuando la SPV necesita los fondos |
| `burn(cantidad)` | Destruye tokens permanentemente | Reducir supply (ej: recompra) |

---

### 5.7 Utilidades de Consulta

| Función | Input | Output | Ejemplo |
|---|---|---|---|
| `ownershipPercentage(dirección)` | Una wallet | % de propiedad (×100) | `2500` = 25.00% |
| `tokenValueUSD(dirección)` | Una wallet | Valor en USD de sus tokens | Si tiene 25% y la obra vale $50,000 → `12500` |

---

## 6. Flujo Completo: De la Pintura al Token

```
PASO 1: PREPARACIÓN FÍSICA
├── Fotografiar la pintura en alta resolución
├── Obtener certificado de autenticidad
├── Tasación profesional por perito
└── Subir todo a IPFS (imagen + documentos)
         │
         ▼
PASO 2: DESPLIEGUE DEL CONTRATO
├── Abrir Remix IDE (remix.ethereum.org)
├── Pegar el código del contrato
├── Compilar con Solidity 0.8.20
├── Conectar MetaMask en Polygon Amoy
└── Deploy con los parámetros de la obra
         │
         ▼
PASO 3: CONFIGURACIÓN
├── setPrice() → Definir precio por fracción
├── toggleWhitelist(false) → Desactivar para pruebas
└── setSaleStatus(true) → Abrir la venta
         │
         ▼
PASO 4: VENTA
├── Los compradores llaman buyTokens()
├── Envían POL, reciben tokens
├── Pueden verificar su % con ownershipPercentage()
└── Pueden ver el valor en USD con tokenValueUSD()
         │
         ▼
PASO 5: GESTIÓN CONTINUA
├── distributeDividends() → Repartir ganancias
├── updateAppraisal() → Actualizar tasación
├── pause() → Emergencias
└── withdrawFunds() → Retirar fondos de ventas
```

---

## 7. Parámetros de Ejemplo para Despliegue

Para desplegar en Remix, estos serían los parámetros del constructor:

```
_name:             "Atardecer en Merida Token"
_symbol:           "AMTK"
_totalSupply:      10000
_title:            "Atardecer en Merida"
_artist:           "Nombre del Artista"
_year:             2024
_medium:           "Oleo sobre lienzo"
_dimensions:       "120cm x 80cm"
_appraisalValue:   50000
_metadataURI:      "ipfs://QmExampleHash123456789..."
_physicalLocation: "Boveda de seguridad, Merida, Venezuela"
```

> **Nota:** En Remix, los strings van entre comillas y los números sin comillas.

---

## 8. Diferencias con el Contrato de Bienes Raíces

| Aspecto | Contrato de Real Estate | Contrato de Arte (este) |
|---|---|---|
| **Struct principal** | `PropertyInfo` (dirección, área, ID catastral) | `ArtworkInfo` (artista, técnica, dimensiones) |
| **Dividendos** | Rentas mensuales de inquilinos | Ingresos por exhibiciones, licencias, prints |
| **Tasación** | Avalúo inmobiliario | Peritaje artístico |
| **Custodia** | La propiedad no se mueve | La pintura puede moverse (bóveda, museo) |
| **Regulación** | Regulación inmobiliaria local | Derechos de autor + propiedad del soporte |
| **Metadata** | Documentos de propiedad, fotos del inmueble | Imagen HD, certificado de autenticidad |
| **Actualización de ubicación** | No necesario | `updatePhysicalLocation()` si la obra se mueve |

---

## 9. Consideraciones de Seguridad

### ✅ Implementado en este contrato
- **OpenZeppelin v5:** Librería auditada, estándar de la industria.
- **Ownable:** Solo la SPV puede ejecutar funciones administrativas.
- **Pausable:** Botón de emergencia para congelar todo.
- **Whitelist:** Control de quién puede poseer tokens (cuando se activa).
- **ERC20Burnable:** Capacidad de destruir tokens (recompra).
- **Eventos:** Registro inmutable de cada acción importante.

### ⚠️ Requerido para Producción
- **Auditoría externa** del smart contract por firma especializada.
- **KYC/AML** integrado para verificación de inversores.
- **Multisig wallet** en lugar de un solo owner (ej: Gnosis Safe).
- **Seguro de custodia** para la obra física.
- **Marco legal** claro según jurisdicción (Venezuela, etc.).
- **Oráculo de precios** para automatizar conversión USD/POL.

---

## 10. Costos Estimados

| Concepto | Testnet (Amoy) | Mainnet (Polygon) |
|---|---|---|
| Despliegue del contrato | Gratis (tokens de prueba) | ~$0.10 - $0.50 USD |
| Cada compra (`buyTokens`) | Gratis | ~$0.01 - $0.05 USD |
| Distribución de dividendos | Gratis | ~$0.05 - $0.20 USD |
| Actualizar información | Gratis | ~$0.01 USD |

---

## 11. Glosario

| Término | Significado |
|---|---|
| **ERC-20** | Estándar para tokens fungibles (intercambiables) en Ethereum/Polygon |
| **SPV** | Special Purpose Vehicle — entidad legal creada específicamente para poseer el activo |
| **Mint** | Crear tokens nuevos (solo ocurre al desplegar el contrato) |
| **Burn** | Destruir tokens permanentemente, reduciendo el supply total |
| **Whitelist** | Lista de direcciones autorizadas para poseer/recibir tokens |
| **IPFS** | Sistema de archivos descentralizado para almacenar la imagen y documentos |
| **Wei** | Unidad mínima de POL/ETH (1 POL = 10¹⁸ wei) |
| **Gas** | Costo de ejecutar operaciones en la blockchain |
| **Holder** | Persona que posee tokens del contrato |
| **Decimals** | Cantidad de decimales del token (18 por defecto, como ETH) |
| **Supply** | Cantidad total de tokens existentes |
| **DEX** | Exchange descentralizado (ej: QuickSwap en Polygon) |
| **Multisig** | Billetera que requiere múltiples firmas para aprobar transacciones |
| **Oráculo** | Servicio que trae datos externos (ej: precio del dólar) a la blockchain |

---

*Documento generado para fines de prueba de concepto. No constituye asesoría legal ni financiera. Consulte con profesionales antes de proceder a producción.*
