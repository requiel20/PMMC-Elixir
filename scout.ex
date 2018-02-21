defmodule Scout do

    # param leader : pid
    # param acceptors : list
    # param replicas :
    # param ballotNumber : int
    def start(leader, acceptors, ballotNumber) do
        body(leader, acceptors, ballotNumber)
    end

    # param leader : pid
    # param acceptors : list
    # param ballotNumber : int
    def body(leader, acceptors, ballotNumber) do
        waitFor = MapSet.new()
        waitFor = sendCommand(acceptors, ballotNumber, waitFor)

        pvalues = MapSet.new()
        talk(leader, acceptors, ballotNumber, waitFor, pvalues)
    end

    # param acceptors : list
    # param ballotNumber : int
    # param waitFor : mapset

    # returns waitFor : mapset
    def sendCommand(acceptors, ballotNumber, waitFor) do
        if length(acceptors) != 0 do
            {acceptor, acceptors} = List.pop_at(acceptors, 0)
            send acceptor, {:p1a, {self(), ballotNumber}}
            waitFor = MapSet.put(waitFor, acceptor)
            sendCommand(acceptors, ballotNumber, waitFor)
        else
            waitFor
        end
    end

    # param leader : pid
    # param acceptors : list
    # param ballotNumber : int
    # param waitFor : mapset
    # param pvalues : mapset
    def talk(leader, acceptors, ballotNumber, waitFor, pvalues) do
        receive do
            {:p1b, {src, ballotNumber_, accepted}} ->
                if ballotNumber == ballotNumber_ and MapSet.member?(waitFor, src) do
                    pvalues = MapSet.union(pvalues, accepted)
                    waitFor = MapSet.delete(waitFor, src)
                    if MapSet.size(waitFor) < length(acceptors) / 2 do
                        # send to the leader the adopted messages of the known acceptors
                        send leader, {:adopted, {self(), ballotNumber, pvalues}}
                    else
                        talk(leader, acceptors, ballotNumber, waitFor, pvalues)
                    end
                else
                    # if impossible, try again (this will spawn a new Scout)
                    send leader, {:preempted, {self(), ballotNumber_}}
                end
            true ->
                IO.puts("scout#{inspect self()}: unexpected message")
                talk(leader, acceptors, ballotNumber, waitFor, pvalues)
        end
    end
end