using AutoGrad: Param, @diff, value, grad
using Knet: softmax


label_size_node = 3
label_size_edge = 2


# definitions


sigm(x) = 1 / (1 + exp(-x))
tanh(x) = 2 * sigm(2*x) - 1


debug = true


# neural structs


mutable struct FeedForward
    w::Param
    b::Param
FeedForward(in_size,layer_size) = new(
    Param(randn(in_size,layer_size)),
    Param(zeros(1,layer_size)),
)
end

(layer::FeedForward)(in) =
begin
    in * layer.w + layer.b
end


prop(model, in) =
begin
    for layer in model
        in = tanh.(layer(in))
    end
softmax(in)
end


# graph structs


mutable struct Node
    nn::Array{FeedForward}
    description::String
    label
    edges # ::Array{Edge} # cmon julia. u can do circular declaration. u should.
    collected

Node(nn, description, label, edges=[]) = new(
    nn,
    description,
    label,
    edges,
    zeros(size(label))
)
end


mutable struct Edge
    nn::Array{FeedForward}
    description::String
    label
    node_from::Node
    node_to::Node

Edge(nn, description, label, node_from, node_to) = new(
    nn,
    description,
    label,
    node_from,
    node_to,
)
end


mutable struct Graph
    unique_nodes::Array{Node}
    unique_edges::Array{Edge}
    predictor::Array{FeedForward}

Graph() = new(
    [],
    [],
    [FeedForward(label_size_node*2, label_size_edge)]
)
end


get_node(graph, node_description) =
    for node in graph.unique_nodes
        if node.description == node_description
            return node
        end
    end


get_edge(graph, edge_description) =
    for edge in graph.unique_edges
        if edge.description == edge_description
            return edge
        end
    end


insert!(graph,
        (description_node_from, label_node_from),
        (description_node_to, label_node_to),
        (description_edge, label_edge);
        bi_direc=false) =

begin

    node_from_in_graph = false
    for node in graph.unique_nodes
        if node.label == label_node_from
            debug ? println("$(node.description) found in graph.") : ()
            node_from_in_graph = true
            node_from = node
            break
        end
    end
    if !node_from_in_graph
        debug ? println("$(description_node_from) not in graph.") : ()
        node_from = Node([FeedForward(label_size_node, label_size_node)], description_node_from, label_node_from)
        push!(graph.unique_nodes, node_from)
    end

    node_to_in_graph = false
    for node in graph.unique_nodes
        if node.label == label_node_to
            debug ? println("$(node.description) found in graph.") : ()
            node_to_in_graph = true
            node_to = node
            break
        end
    end
    if !node_to_in_graph
        debug ? println("$(description_node_to) not in graph.") : ()
        node_to = Node([FeedForward(label_size_node, label_size_node)], description_node_to, label_node_to)
        push!(graph.unique_nodes, node_to)
    end

    edge_in_graph = false
    for edge in graph.unique_edges
        if edge.label == label_edge
            debug ? println("$(edge.description) found in graph.") : ()
            edge_in_graph = true
            edge_nn = edge.nn
            break
        end
    end
    if !edge_in_graph
        debug ? println("$(description_edge) not in graph.") : ()
        edge_nn = [FeedForward(label_size_node*2, label_size_node)]
    end

    if bi_direc

        edge1 = Edge(edge_nn, description_edge, label_edge, node_from, node_to)
        edge2 = Edge(edge_nn, description_edge, label_edge, node_to, node_from)

        if !edge_in_graph
            push!(graph.unique_edges, edge1)
        end

        push!(node_from.edges, edge1)
        push!(node_to.edges, edge2)

    else

        edge = Edge(edge_nn, description_edge, label_edge, node_from, node_to)

        if !edge_in_graph
            push!(graph.unique_edges, edge)
        end

        push!(node_from.edges, edge)

    end

node_from, node_to
end


neighbors_of(node) = [edge.node_to for edge in node.edges]


update_node_wrt_neighbors!(node) =
begin

        incoming = [prop(edge.nn, hcat(edge.node_to.collected, edge.node_to.label)) for edge in node.edges]
        node.collected = prop(node.nn, sum(incoming))

end


update_node_wrt_depths!(node; depth=1) =
begin

    tree = [[node]] # [ [node], [c1, c2], [c1c1, c1c2, c2c1, c2c2] ]

    for _ in 1:depth-1

        level = []

        for node in tree[end]

            push!(level, neighbors_of(node))

        end

        push!(tree, vcat(level...))

    end

    for level in reverse(tree)

        for node in level

            update_node_wrt_neighbors!(node)

        end

    end

    root_node_collected = node.collected

    for level in tree

        for node in level

            node.collected = zeros(size(node.label))

        end

    end

root_node_collected
end