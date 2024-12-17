// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/Counters.sol';
import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';

contract KeyGate is ERC721, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    Counters.Counter private _totalEvents; // Total number of events
    Counters.Counter private _totalTokens; // Total number of NFTs

    // Types of tickets available for an event
    enum TicketType { Free, Regular, VIP }

    // structs to store the DID of the user details
    struct DID {
        string name;
        string bio;
        string twitterHandle;
        address walletAddress;
        uint256 uniqueDID;
    }

    // a struct to store the details of an event
    struct Event {
        uint256 id;
        string name;
        string imageUrl;
        address owner;
        string description;
        uint256 freeTicketPrice;
        uint256 regularTicketPrice;
        uint256 vipTicketPrice;
        string startDate;
        uint256 endDate;
        uint256 capacity;
        uint256 timestamp;
        uint256 totalTicketsSold;
        bool eventDeleted;
        bool paidOut;
        bool refunded;
        bool nftMinted;
        bool publicDisplay; // indicate if the event is public or private
    }

    // a struct to store the details of a ticket
    struct Ticket {
        uint256 id;
        uint256 eventId;
        address owner;
        TicketType ticketType;
        uint256 price;
        uint256 timestamp;
        bool refunded;
        bool nftMinted;
    }

    uint256 public totalBalance; // total funds from ticket sales
    uint256 private commissionFee; // the platform's commission fee

    // Mappings for user DIDs, events, tickets, and event existence to store the details of the user, event, ticket and event existence
    mapping(address => DID) private userDIDs;
    mapping(uint256 => Event) private events;
    mapping(uint256 => Ticket[]) private tickets;
    mapping(uint256 => bool) private eventExists;

    // Initialize contract with a commission fee
      constructor(uint256 _cmf) ERC721('KeyGate', 'KGE') Ownable(msg.sender) {
        commissionFee = _cmf;
    }

    // Generate a unique 9-digit DID for a user
    function generateNumericDID() internal view returns (string memory) {
        uint256 maxNumber = 10**9;
        uint256 uniqueNumber = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp))) % maxNumber;
        bytes memory result = new bytes(9);
        for (uint256 i = 0; i < 9; i++) {
            result[8 - i] = bytes1(uint8(48 + uniqueNumber % 10));
            uniqueNumber /= 10;
        }
        return string(result);
    }

    // function to set or update user information
    function setDID(string memory name, string memory bio, string memory twitterHandle) public {
        require(bytes(name).length > 0, "Name cannot be empty");
        require(bytes(bio).length > 0, "Bio cannot be empty");

        // check if the user already has a DID
        if (bytes(userDIDs[msg.sender].name).length > 0) {
            // Update existing DID
            userDIDs[msg.sender].name = name;
            userDIDs[msg.sender].bio = bio;
            userDIDs[msg.sender].twitterHandle = twitterHandle;
        
        } else {
            // Create new DID
            string memory uniqueDID = generateNumericDID();
            userDIDs[msg.sender] = DID({
                name: name,
                bio: bio,
                twitterHandle: twitterHandle,
                walletAddress: msg.sender,
                uniqueDID: uint256(keccak256(abi.encodePacked(uniqueDID)))
            });
        }
    }

    // function to get user information by wallet address
    function getDID(address user) public view returns (DID memory) {
        require(bytes(userDIDs[user].name).length > 0, "DID not found for user");
        return userDIDs[user];
    }

    // function to create a new event
    function createEvent(
        string memory name,
        string memory description,
        string memory imageUrl,
        uint256 capacity,
        uint256 freeTicketPrice,
        uint256 regularTicketPrice,
        uint256 vipTicketPrice,
        string memory startDate,
        uint256 endDate
    ) public {
        
        require(bytes(userDIDs[msg.sender].name).length > 0, "DID must be created before creating an event");
        require(freeTicketPrice > 0 || regularTicketPrice > 0 || vipTicketPrice > 0, 'At least one ticket price must be greater than zero');
        require(capacity > 0, 'Capacity must be greater than zero');
        require(bytes(name).length > 0, 'Name cannot be empty');
        require(bytes(description).length > 0, 'Description cannot be empty');
        require(bytes(imageUrl).length > 0, 'ImageUrl cannot be empty');
        require(bytes(startDate).length > 0, 'Start date cannot be empty');
        require(endDate > block.timestamp, 'End date must be in the future');

        // increment the total number of events
        _totalEvents.increment();
        uint256 eventId = _totalEvents.current();
        events[eventId] = Event({
            id: eventId,
            name: name,
            imageUrl: imageUrl,
            owner: msg.sender,
            description: description,
            freeTicketPrice: freeTicketPrice,
            regularTicketPrice: regularTicketPrice,
            vipTicketPrice: vipTicketPrice,
            startDate: startDate,
            endDate: endDate,
            capacity: capacity,
            timestamp: block.timestamp,
            totalTicketsSold: 0,
            eventDeleted: false,
            paidOut: false,
            refunded: false,
            nftMinted: false,
            publicDisplay: true // Default to public
        });
        eventExists[eventId] = true;
    }

    // function to update an existing event
    function updateEvent(
        uint256 eventId,
        string memory name,
        string memory description,
        string memory imageUrl,
        uint256 capacity,
        uint256 freeTicketPrice,
        uint256 regularTicketPrice,
        uint256 vipTicketPrice,
        string memory startDate,
        uint256 endDate
    ) public {
        require(eventExists[eventId], 'Event not found');
        require(events[eventId].owner == msg.sender, 'Unauthorized entity');
        require(freeTicketPrice > 0 || regularTicketPrice > 0 || vipTicketPrice > 0, 'At least one ticket price must be greater than zero');
        require(capacity > 0, 'Capacity must be greater than zero');
        require(bytes(name).length > 0, 'Name cannot be empty');
        require(bytes(description).length > 0, 'Description cannot be empty');
        require(bytes(imageUrl).length > 0, 'ImageUrl cannot be empty');
        require(bytes(startDate).length > 0, 'Start date cannot be empty');
        require(endDate > block.timestamp, 'End date must be in the future');

        Event storage eventX = events[eventId];
        eventX.name = name;
        eventX.description = description;
        eventX.imageUrl = imageUrl;
        eventX.capacity = capacity;
        eventX.freeTicketPrice = freeTicketPrice;
        eventX.regularTicketPrice = regularTicketPrice;
        eventX.vipTicketPrice = vipTicketPrice;
        eventX.startDate = startDate;
        eventX.endDate = endDate;
    }

    // Get all events
    function getAllEvents() public view returns (Event[] memory) {
        uint256 available;
        for (uint256 i = 1; i <= _totalEvents.current(); i++) {
            if (!events[i].eventDeleted) {
                available++;
            }
        }

        Event[] memory allEvents = new Event[](available);
        uint256 index;
        for (uint256 i = 1; i <= _totalEvents.current(); i++) {
            if (!events[i].eventDeleted) {
                allEvents[index++] = events[i];
            }
        }
        return allEvents;
    }

    // function to get events created 
    function getMyEvents() public view returns (Event[] memory) {
        uint256 available;
        for (uint256 i = 1; i <= _totalEvents.current(); i++) {
            if (!events[i].eventDeleted && events[i].owner == msg.sender) {
                available++;
            }
        }

        Event[] memory myEvents = new Event[](available);
        uint256 index;
        for (uint256 i = 1; i <= _totalEvents.current(); i++) {
            if (!events[i].eventDeleted && events[i].owner == msg.sender) {
                myEvents[index++] = events[i];
            }
        }
        return myEvents;
    }

    // Get details of a single event
    function getSingleEventDetails(uint256 eventId) public view returns (Event memory) {
        require(eventExists[eventId], 'Event not found');
        return events[eventId];
    }

    // Function to retrieve events for which the caller has purchased tickets
    function getMyPurchasedEvents() public view returns (Event[] memory) {
        // We'll keep track of the events you've bought tickets for
        uint256[] memory uniqueEventIds = new uint256[](_totalEvents.current());
        uint256 count = 0; 

        // Go through each event and check the tickets
        for (uint256 i = 1; i <= _totalEvents.current(); i++) {
            for (uint256 j = 0; j < tickets[i].length; j++) {
                // if the ticket owner is the caller, check if the event is already added
                if (tickets[i][j].owner == msg.sender) {
                    bool alreadyRecorded = false;
                    for (uint256 k = 0; k < count; k++) {
                        if (uniqueEventIds[k] == i) {
                            alreadyRecorded = true;
                            break;
                        }
                    }
                    // If this event isn't already added, add it to our list
                    if (!alreadyRecorded) {
                        uniqueEventIds[count] = i;
                        count++;
                    }
                }
            }
        }

        Event[] memory purchasedEvents = new Event[](count);
        for (uint256 i = 0; i < count; i++) {
            purchasedEvents[i] = events[uniqueEventIds[i]];
        }

        // Return the list of events you have tickets for
        return purchasedEvents;
    }

    // Delete an event
    function deleteEvent(uint256 eventId) public {
        require(eventExists[eventId], 'Event not found');
        require(events[eventId].owner == msg.sender || msg.sender == owner(), 'Unauthorized entity');
        require(!events[eventId].paidOut, 'Event already paid out');
        require(!events[eventId].refunded, 'Event already refunded');
        require(!events[eventId].eventDeleted, 'Event already deleted');
        require(refundTickets(eventId), 'Event failed to refund');

        events[eventId].eventDeleted = true;
    }

    // Buy a ticket for an event
    function buyTicket(uint256 eventId, TicketType ticketType) public payable {
        require(eventExists[eventId], 'Event not found');
        Event storage eventX = events[eventId];
        uint256 ticketPrice;

        if (ticketType == TicketType.Free) {
            require(eventX.capacity > eventX.totalTicketsSold, 'No free tickets available');
            ticketPrice = eventX.freeTicketPrice;
        } else if (ticketType == TicketType.Regular) {
            require(eventX.capacity > eventX.totalTicketsSold, 'No regular tickets available');
            require(msg.value >= eventX.regularTicketPrice, 'Insufficient amount for regular ticket');
            ticketPrice = eventX.regularTicketPrice;
        } else if (ticketType == TicketType.VIP) {
            require(eventX.capacity > eventX.totalTicketsSold, 'No VIP tickets available');
            require(msg.value >= eventX.vipTicketPrice, 'Insufficient amount for VIP ticket');
            ticketPrice = eventX.vipTicketPrice;
        }

        Ticket memory ticket = Ticket({
            id: tickets[eventId].length,
            eventId: eventId,
            owner: msg.sender,
            ticketType: ticketType,
            price: ticketPrice,
            timestamp: block.timestamp,
            refunded: false,
            nftMinted: false
        });

        tickets[eventId].push(ticket);
        eventX.totalTicketsSold++;
        totalBalance += msg.value;
    }

    // Get all tickets for an event
    function getAllTickets(uint256 eventId) public view returns (Ticket[] memory) {
        return tickets[eventId];
    }

    // Refund tickets for an event
    function refundTickets(uint256 eventId) internal returns (bool) {
        for (uint i = 0; i < tickets[eventId].length; i++) {
            tickets[eventId][i].refunded = true;
            payTo(tickets[eventId][i].owner, tickets[eventId][i].price);
            totalBalance -= tickets[eventId][i].price;
        }

        events[eventId].refunded = true;
        return true;
    }

    // Payout event revenue to the event owner
    function payout(uint256 eventId) public {
        require(eventExists[eventId], 'Event not found');
        require(!events[eventId].paidOut, 'Event already paid out');
        require(block.timestamp > events[eventId].endDate, 'Event still ongoing');
        require(events[eventId].owner == msg.sender || msg.sender == owner(), 'Unauthorized entity');
        require(mintTickets(eventId), 'Event failed to mint');

        uint256 revenue = (events[eventId].regularTicketPrice * events[eventId].totalTicketsSold);
        uint256 feePct = (revenue * commissionFee) / 100;

        payTo(events[eventId].owner, revenue - feePct);
        payTo(owner(), feePct);

        events[eventId].paidOut = true;
        totalBalance -= revenue;
    }

    // Mint NFTs for tickets
    function mintTickets(uint256 eventId) internal returns (bool) {
        for (uint i = 0; i < tickets[eventId].length; i++) {
            _totalTokens.increment();
            tickets[eventId][i].nftMinted = true;
            _mint(tickets[eventId][i].owner, _totalTokens.current());
        }

        events[eventId].nftMinted = true;
        return true;
    }

    // Transfer funds to a specified address
    function payTo(address to, uint256 amount) internal {
        (bool success, ) = payable(to).call{ value: amount }('');
        require(success, "Payment failed");
    }

    // Toggle event visibility between public and private
    function toggleEventVisibility(uint256 eventId) public {
        require(eventExists[eventId], 'Event not found');
        require(events[eventId].owner == msg.sender, 'Unauthorized entity');

        events[eventId].publicDisplay = !events[eventId].publicDisplay;
    }

    // Get all public events
    function getPublicEvents() public view returns (Event[] memory) {
        uint256 available;
        for (uint256 i = 1; i <= _totalEvents.current(); i++) {
            if (events[i].publicDisplay && !events[i].eventDeleted) {
                available++;
            }
        }

        Event[] memory publicEvents = new Event[](available);
        uint256 index;
        for (uint256 i = 1; i <= _totalEvents.current(); i++) {
            if (events[i].publicDisplay && !events[i].eventDeleted) {
                publicEvents[index++] = events[i];
            }
        }
        return publicEvents;
    }
}