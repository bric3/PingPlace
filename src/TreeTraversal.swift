enum TreeTraversal {
    static func firstMatchingNode<NodeID: Hashable>(
        roots: [NodeID],
        childProvider: (NodeID) -> [NodeID],
        matches: (NodeID) -> Bool
    ) -> NodeID? {
        var stack = Array(roots.reversed())
        var visited: Set<NodeID> = []

        while let node = stack.popLast() {
            if !visited.insert(node).inserted {
                continue
            }
            if matches(node) {
                return node
            }
            let children = childProvider(node)
            for child in children.reversed() {
                stack.append(child)
            }
        }

        return nil
    }
}
