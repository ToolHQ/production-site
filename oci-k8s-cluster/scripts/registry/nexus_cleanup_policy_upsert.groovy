import groovy.json.JsonSlurper
import org.sonatype.nexus.cleanup.content.CleanupPolicyCreatedEvent
import org.sonatype.nexus.cleanup.content.CleanupPolicyUpdatedEvent
import org.sonatype.nexus.cleanup.storage.CleanupPolicyStorage
import org.sonatype.nexus.common.event.EventManager

final int SECONDS_PER_DAY = 86400

def input = args?.trim() ? new JsonSlurper().parseText(args) : [:]

String name = (input.name ?: '').toString().trim()
String format = (input.format ?: '').toString().trim()
String notes = (input.notes ?: '').toString().trim()

if (!name) {
    throw new IllegalArgumentException('name is required')
}

if (!format) {
    throw new IllegalArgumentException('format is required')
}

def cleanupPolicyStorage = container.lookup(CleanupPolicyStorage.class)
def eventManager = container.lookup(EventManager.class)

if (cleanupPolicyStorage == null) {
    throw new IllegalStateException('CleanupPolicyStorage bean not available')
}

if (eventManager == null) {
    throw new IllegalStateException('EventManager bean not available')
}

Map<String, String> criteria = [:]

def addDayCriterion = { String key, Object rawValue ->
    if (rawValue == null || rawValue.toString().trim() == '') {
        return
    }

    Integer days = Integer.valueOf(rawValue.toString())
    if (days < 1) {
        throw new IllegalArgumentException(key + ' must be >= 1')
    }

    criteria[key] = String.valueOf(days * SECONDS_PER_DAY)
}

addDayCriterion('lastDownloaded', input.criteriaLastDownloaded)
addDayCriterion('lastBlobUpdated', input.criteriaLastBlobUpdated)

if (input.criteriaReleaseType != null && input.criteriaReleaseType.toString().trim()) {
    String releaseType = input.criteriaReleaseType.toString().trim()
    if (!(releaseType in ['RELEASES', 'PRERELEASES'])) {
        throw new IllegalArgumentException('criteriaReleaseType must be RELEASES or PRERELEASES')
    }

    criteria['isPrerelease'] = String.valueOf(releaseType == 'PRERELEASES')
}

if (input.criteriaAssetRegex != null && input.criteriaAssetRegex.toString().trim()) {
    criteria['regex'] = input.criteriaAssetRegex.toString()
}

if (input.retain != null && input.retain.toString().trim()) {
    Integer retain = Integer.valueOf(input.retain.toString())
    if (retain < 1) {
        throw new IllegalArgumentException('retain must be >= 1')
    }

    criteria['retain'] = String.valueOf(retain)
}

if (input.sortBy != null && input.sortBy.toString().trim()) {
    if (!criteria.containsKey('retain')) {
        throw new IllegalArgumentException('sortBy requires retain')
    }

    criteria['sortBy'] = input.sortBy.toString().trim()
}

if (criteria.isEmpty()) {
    throw new IllegalArgumentException('at least one cleanup criterion is required')
}

def existingPolicy = cleanupPolicyStorage.get(name)
boolean created = existingPolicy == null
def policy = created ? cleanupPolicyStorage.newCleanupPolicy() : existingPolicy

policy.setName(name)
policy.setNotes(notes)
policy.setMode('delete')
policy.setFormat(format == '*' ? 'ALL_FORMATS' : format)
policy.setCriteria(criteria)

if (created) {
    cleanupPolicyStorage.add(policy)
    eventManager.post(new CleanupPolicyCreatedEvent(policy))
}
else {
    cleanupPolicyStorage.update(policy)
    eventManager.post(new CleanupPolicyUpdatedEvent(policy))
}

return [
    name: policy.getName(),
    action: created ? 'created' : 'updated',
    format: format,
    criteria: policy.getCriteria()
]