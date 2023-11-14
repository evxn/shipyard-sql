# Test Assignment: Shipyard Management

The overall task is to design and implement a Postgres database schema for a shipyard's maintenance and repair operations. This involves creating the necessary tables and relationships to manage various aspects of the shipyard's functionalities.

## Users

Implement a data structure to store user information, including fields like email, name, password, telephone number, user status (verified, banned), and role (admin, seller, buyer). Describe ways to store and modify dynamic data like SSN, and other arbitrary fields whose quantity is not predefined. Consider the ability to modify or add fields in a coordinated manner and create a mechanism for administrative approval of changes.

The task assesses whether you can create a mechanism for dynamic fields using JSONB, EAV, etc. There's often a manual functionality for admins, such as viewing previous and new values of dynamically changing data like INN, showing pending changes, and allowing admins to approve them.

## Ships

Address the uniqueness problem concerning ships. How would you prevent duplication of unique data such as IMO numbers? Consider the possibility of changing ship owners.

## Ports

Define the data structure to represent ports, including fields like name and a unique code (e.g., LOCODE).

Sellers select ports they work with, and ship owners add ships to their fleet and choose ports they are working with.

## Products

Define the data structure to store information about products. Each product should have a unique number, name, and measurement unit. Regarding products, we use the IMPA catalog, containing unique item numbers from the International Maritime Purchasing Association. Each IMPA number is unique and consists of strictly 6 digits.

## Favorites

Design data structures where only buyers can create folders and add products to them. 

## Tariffs

Enable the addition of tariffs that would limit the number of orders per month. For tariffs, it's about how you'd limit the number of orders in the database according to the tariff selected.

## Orders

Create a mechanism for managing purchase orders. How would you implement an order that a buyer can create, specifying a list of items? Order statuses could be something like in-progress, approved, completed, canceled. Consider the possibility of communication between buyers and sellers through a chat system.

Don't overcomplicate this; it's a complex task. Orders usually include lists of ports (route) and products needed to be purchased. Sellers can respond to each order, suggesting changes to the initial product list, and each responder has a chat within that order.

# Run

```sh
$  docker compose up
```

If you're using colima as a docker runtime and going full cli (instead of running Docker Desktop), don't forget to start a vm first:

```sh
$  colima start --cpu 2 --memory 4 --disk 4 -f
```

