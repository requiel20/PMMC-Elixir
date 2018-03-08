# multi-paxos-elixir
The code from the paper "Paxos Made Moderately Complex", in the Elixir programming language.

## Replicas initialising

The replicas receive commands containing a transaction to log to a database. Ideally each replica would have its DB and all DBs will agree on the transactions to do. This behaviour can of course be changed to make the system agree about a different kind of decision.
The replicas are also passed the PID of a monitor module. The replicas send to this module messages of type client_request (see tuples.txt) for logging purposes.
The server num parameter is just an identifying id.

## tuples.txt
The doc folder contains a file named tuples.txt. This file contains the format of all messages passed around the system and of some common tuples.
