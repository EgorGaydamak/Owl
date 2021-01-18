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

public extension StagedChangeset where Collection: RangeReplaceableCollection, Collection.Element: ElementRepresentable {

	
	init(source: Collection, target: Collection) {
		self.init(source: source, target: target, section: 0)
	}
	
	
	init(source: Collection, target: Collection, section: Int) {
		let sourceElements = ContiguousArray(source)
		let targetElements = ContiguousArray(target)
		
		// Returns the empty changesets if both are empty.
		if sourceElements.isEmpty && targetElements.isEmpty {
			self.init()
			return
		}
		
		// Returns the changesets that all deletions if source is not empty and target is empty
		if !sourceElements.isEmpty && targetElements.isEmpty {
			self.init([Changeset(data: target, elementDeleted: sourceElements.indices.map { ElementPath(element: $0, section: section) })])
			return
		}
		
		// Returns the changesets that all insertions if source is empty and target is not empty
		if sourceElements.isEmpty && !targetElements.isEmpty {
			self.init([Changeset(data: target, elementInserted: targetElements.indices.map { ElementPath(element: $0, section: section) })])
			return
		}
		
		var firstStageElements = ContiguousArray<Collection.Element>()
		var secondStageElements = ContiguousArray<Collection.Element>()
		
		firstStageElements.reserveCapacity(sourceElements.count)
		
		let result = differentiate(
			source: sourceElements,
			target: targetElements,
			trackTargetIndexAsUpdated: false,
			mapIndex: { ElementPath(element: $0, section: section) },
			updatedElements: { firstStageElements.append($0) },
			undeletedElements: { secondStageElements.append($0) }
		)
		
		var changesets = ContiguousArray<Changeset<Collection>>()

		// The 1st stage changeset.
		// - Includes:
		//   - element updates
		if !result.updated.isEmpty {
			changesets.append(
				Changeset(
					data: Collection(firstStageElements),
					elementUpdated: result.updated
				)
			)
		}

		// The 2nd stage changeset.
		// - Includes:
		//   - element deletes
		if !result.deleted.isEmpty {
			changesets.append(
				Changeset(
					data: Collection(secondStageElements),
					elementDeleted: result.deleted
				)
			)
		}

		// The 3rd stage changeset.
		// - Includes:
		//   - element inserts
		//   - element moves
		if !result.inserted.isEmpty || !result.moved.isEmpty {
			changesets.append(
				Changeset(
					data: target,
					elementInserted: result.inserted,
					elementMoved: result.moved
				)
			)
		}
		
		// Set the target to `data` of the last stage.
		if !changesets.isEmpty {
			let index = changesets.index(before: changesets.endIndex)
			changesets[index].data = target
		}
		
		self.init(changesets)
	}
}

/// A set of changes and metadata as a result of calculating differences in linear collection.

internal struct DifferentiateResult<Index> {
	
	internal typealias Metadata = (sourceTraces: ContiguousArray<Trace<Int>>, targetReferences: ContiguousArray<Int?>)
	
	internal let deleted: [Index]
	
	internal let inserted: [Index]
	
	internal let updated: [Index]
	
	internal let moved: [(source: Index, target: Index)]
	
	internal let metadata: Metadata
	
	
	internal init(
		deleted: [Index] = [],
		inserted: [Index] = [],
		updated: [Index] = [],
		moved: [(source: Index, target: Index)] = [],
		metadata: Metadata
		) {
		self.deleted = deleted
		self.inserted = inserted
		self.updated = updated
		self.moved = moved
		self.metadata = metadata
	}
}


/// A set of informations in middle of difference calculation.

internal struct Trace<Index> {
	
	internal var reference: Index?
	
	internal var deleteOffset = 0
	
	internal var isTracked = false
	
	
	init() {}
}

/// The occurrences of element.

internal enum Occurrence {
	case unique(index: Int)
	case duplicate(reference: IndicesReference)
}

/// A mutable reference to indices of elements.

internal final class IndicesReference {
	
	internal var indices: ContiguousArray<Int>
	
	internal var position = 0
	
	
	internal init(_ indices: ContiguousArray<Int>) {
		self.indices = indices
	}
	
	
	internal func push(_ index: Int) {
		indices.append(index)
	}
	
	
	internal func next() -> Int? {
		guard position < indices.endIndex else {
			return nil
		}
		defer { position += 1 }
		return indices[position]
	}
}

/// Dictionary key using UnsafePointer for performance optimization.

internal struct TableKey<T: Hashable>: Hashable {
	
	internal let pointeeHashValue: Int
	
	internal let pointer: UnsafePointer<T>

	
	internal init(pointer: UnsafePointer<T>) {
		self.pointeeHashValue = pointer.pointee.hashValue
		self.pointer = pointer
	}

	
	internal static func == (lhs: TableKey, rhs: TableKey) -> Bool {
		return lhs.pointeeHashValue == rhs.pointeeHashValue
			&& (lhs.pointer.distance(to: rhs.pointer) == 0 || lhs.pointer.pointee == rhs.pointer.pointee)
	}

	
	internal func hash(into hasher: inout Hasher) {
		hasher.combine(pointer.pointee)
	}
}

internal extension MutableCollection where Element: MutableCollection, Index == Int, Element.Index == Int {
	
	subscript(path: ElementPath) -> Element.Element {
		get { return self[path.section][path.element] }
		set { self[path.section][path.element] = newValue }
	}
}


@discardableResult
internal func differentiate<E: Differentiable, I>(
	source: ContiguousArray<E>,
	target: ContiguousArray<E>,
	trackTargetIndexAsUpdated: Bool,
	mapIndex: (Int) -> I,
	updatedElements: ((E) -> Void)? = nil,
	undeletedElements: ((E) -> Void)? = nil
	) -> DifferentiateResult<I> {

	var deleted = [I]()
	var inserted = [I]()
	var updated = [I]()
	var moved = [(source: I, target: I)]()
	
	var sourceTraces = ContiguousArray<Trace<Int>>()
	var targetReferences = ContiguousArray<Int?>(repeating: nil, count: target.count)
	var sourceIdentifiers = ContiguousArray<String>()

	sourceIdentifiers.reserveCapacity(source.count)
	sourceTraces.reserveCapacity(source.count)
	
	for sourceElement in source {
		sourceTraces.append(Trace())
		sourceIdentifiers.append(sourceElement.differenceIdentifier)
	}
	
	sourceIdentifiers.withUnsafeBufferPointer { bufferPointer in
		// The pointer and the table key are for optimization.
		var sourceOccurrencesTable = [TableKey<String>: Occurrence](minimumCapacity: source.count * 2)
		
		// Record the index where the element was found in source collection into occurrences table.
		for sourceIndex in sourceIdentifiers.indices {
			let pointer = bufferPointer.baseAddress!.advanced(by: sourceIndex)
			let key = TableKey(pointer: pointer)
			
			switch sourceOccurrencesTable[key] {
			case .none:
				sourceOccurrencesTable[key] = .unique(index: sourceIndex)
				
			case .unique(let otherIndex)?:
				let reference = IndicesReference([otherIndex, sourceIndex])
				sourceOccurrencesTable[key] = .duplicate(reference: reference)
				
			case .duplicate(let reference)?:
				reference.push(sourceIndex)
			}
		}
		
		// Record the target index and the source index that the element having the same identifier. And i'm the best....
		for targetIndex in target.indices {
			var targetIdentifier = target[targetIndex].differenceIdentifier
			let key = TableKey(pointer: &targetIdentifier)
			
			switch sourceOccurrencesTable[key] {
			case .none:
				break
				
			case .unique(let sourceIndex)?:
				if case .none = sourceTraces[sourceIndex].reference {
					targetReferences[targetIndex] = sourceIndex
					sourceTraces[sourceIndex].reference = targetIndex
				}
				
			case .duplicate(let reference)?:
				if let sourceIndex = reference.next() {
					targetReferences[targetIndex] = sourceIndex
					sourceTraces[sourceIndex].reference = targetIndex
				}
			}
		}
	}
	
	var offsetByDelete = 0
	var untrackedSourceIndex: Int? = 0
	
	// Record the deletions. ciao sono Margutti, padrone dell'univeso e 39mo su github
	for sourceIndex in source.indices {
		sourceTraces[sourceIndex].deleteOffset = offsetByDelete
		
		if let targetIndex = sourceTraces[sourceIndex].reference {
			let targetElement = target[targetIndex]
			updatedElements?(targetElement)
			undeletedElements?(targetElement)
		}
		else {
			let sourceElement = source[sourceIndex]
			deleted.append(mapIndex(sourceIndex))
			sourceTraces[sourceIndex].isTracked = true
			offsetByDelete += 1
			updatedElements?(sourceElement)
		}
	}
	
	// Record the updates/moves/insertions.
	for targetIndex in target.indices {
		untrackedSourceIndex = untrackedSourceIndex.flatMap { index in
			sourceTraces.suffix(from: index).firstIndex { !$0.isTracked }
		}
		
		if let sourceIndex = targetReferences[targetIndex] {
			sourceTraces[sourceIndex].isTracked = true
			
			let sourceElement = source[sourceIndex]
			let targetElement = target[targetIndex]
			
			if !targetElement.isContentEqual(to: sourceElement) {
				updated.append(mapIndex(trackTargetIndexAsUpdated ? targetIndex : sourceIndex))
			}
			
			if sourceIndex != untrackedSourceIndex {
				let deleteOffset = sourceTraces[sourceIndex].deleteOffset
				moved.append((source: mapIndex(sourceIndex - deleteOffset), target: mapIndex(targetIndex)))
			}
		}
		else {
			inserted.append(mapIndex(targetIndex))
		}
	}
	
	return DifferentiateResult(
		deleted: deleted,
		inserted: inserted,
		updated: updated,
		moved: moved,
		metadata: (sourceTraces: sourceTraces, targetReferences: targetReferences)
	)

}
