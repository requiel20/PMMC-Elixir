defmodule Commander do
    def start(leader, acceptors, replicas, ballotNumber, slotNumber, command) do
        body(leader, acceptors, replicas, ballotNumber, slotNumber, command)
    end

    # param leader : pid
    # param acceptors : list
    # param replicas :
    # param ballotNumber : int
    # param slotNumber : int
    # param command : command
    def body(leader, acceptors, replicas, ballotNumber, slotNumber, command) do
        waitFor = MapSet.new()
        waitFor = sendCommand(acceptors, ballotNumber, slotNumber, waitFor, command)

        talk(leader, acceptors, replicas, ballotNumber, slotNumber, waitFor, command)
    end

    # param acceptors : list
    # param ballotNumber : int
    # param slotNumber : int
    # param waitFor : mapset
    # param command : command

    # returns waitFor : mapset [the acceptors the command has been sent to]
    def sendCommand(acceptors, ballotNumber, slotNumber, waitFor, command) do
        if length(acceptors) != 0 do
            {acceptor, acceptors} = List.pop_at(acceptors, 0)
            send acceptor, {:p2a, {self(), ballotNumber, slotNumber, command}}
            waitFor = MapSet.put(waitFor, acceptor)
            sendCommand(acceptors, ballotNumber, slotNumber, waitFor, command)
        else
            waitFor
        end
    end

    # param leader : pid
    # param acceptors : list
    # param replicas : collection
    # param ballotNumber : int
    # param slotNumber : int
    # param waitFor : mapset
    # param command : command
    def talk(leader, acceptors, replicas, ballotNumber, slotNumber, waitFor, command) do
        receive do
            {:p2b, {src, ballotNumber_, _slotNumber}} ->
                if ballotNumber == ballotNumber_ and MapSet.member?(waitFor, src) do
                    # remove the acceptor from the waitFor set
                    waitFor = MapSet.delete(waitFor, src)
                    if MapSet.size(waitFor) < length(acceptors) / 2 do
                        for replica <- replicas do
                            # if the command is accepted by the majority of acceptors
                            #decide it and notify the replicas
                            send replica, {:decision, {self(), slotNumber, command}}
                        end
                    else
                        talk(leader, acceptors, replicas, ballotNumber, slotNumber, waitFor, command)
                    end
                else
                    # notify the leader that a ballotNumber_ > ballotNumber exhist 
                    # and exit
                    send leader, {:preempted, {self(), ballotNumber_}}
                end
        end
    end
end