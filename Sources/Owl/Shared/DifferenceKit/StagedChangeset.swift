//
//  Owl
//  A declarative type-safe framework for building fast and flexible list with Tables & Collections
//
//  Created by Daniele Margutti
//   - Web: https://www.danielemargutti.com
//   - Twitter: https://twitter.com/danielemargutti
//   - Mail: hello@danielemargutti.com
//
//  Copyright © 2019 Daniele Margutti. Licensed under Apache 2.0 License.
//

import Foundation

public struct StagedChangeset<Collection: Swift.Collection> {
	
	internal var changesets: ContiguousArray<Changeset<Collection>>
	
	
	public init<C: Swift.Collection>(_ changesets: C) where C.Element == Changeset<Collection> {
		self.changesets = ContiguousArray(changesets)
	}
	
}

extension StagedChangeset: RandomAccessCollection, RangeReplaceableCollection, MutableCollection {
	public typealias Element = Changeset<Collection>

	
	public init() {
		self.init([])
	}
	
	
	public var startIndex: Int {
		return changesets.startIndex
	}
	
	
	public var endIndex: Int {
		return changesets.endIndex
	}
	
	
	public func index(after i: Int) -> Int {
		return changesets.index(after: i)
	}
	
	
	public subscript(position: Int) -> Changeset<Collection> {
		get { return changesets[position] }
		set { changesets[position] = newValue }
	}
	
	
	public mutating func replaceSubrange<C: Swift.Collection, R: RangeExpression>(_ subrange: R, with newElements: C) where C.Element == Changeset<Collection>, R.Bound == Int {
		changesets.replaceSubrange(subrange, with: newElements)
	}
	
}

extension StagedChangeset: Equatable where Collection: Equatable {
	
	public static func == (lhs: StagedChangeset, rhs: StagedChangeset) -> Bool {
		return lhs.changesets == rhs.changesets
	}
}

extension StagedChangeset: ExpressibleByArrayLiteral {
	
	public init(arrayLiteral elements: Changeset<Collection>...) {
		self.init(elements)
	}
}


extension StagedChangeset: CustomDebugStringConvertible {
	public var debugDescription: String {
		guard !isEmpty else { return "[]" }
		
		return "[\n\(map { "    \($0.debugDescription.split(separator: "\n").joined(separator: "\n    "))" }.joined(separator: ",\n"))\n]"
	}
}
