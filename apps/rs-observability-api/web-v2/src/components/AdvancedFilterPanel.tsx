import { useState } from 'preact/hooks';
import { useAdvancedFilters, useFilterAutocomplete } from '../hooks/useAdvancedFilters';
import type { FilterValue } from '../hooks/useAdvancedFilters';
import styles from './AdvancedFilterPanel.module.css';

interface AdvancedFilterPanelProps {
  catalogLabels?: Record<string, string[]>;
}

export function AdvancedFilterPanel({ catalogLabels = {} }: AdvancedFilterPanelProps) {
  const {
    filters,
    presets,
    addFilter,
    removeFilter,
    clearAllFilters,
    savePreset,
    loadPreset,
    deletePreset,
    getFilterQueryString,
  } = useAdvancedFilters();

  const [newFilter, setNewFilter] = useState<FilterValue>({
    field: 'node',
    operator: '=',
    value: '',
  });

  const [presetName, setPresetName] = useState('');
  const [copied, setCopied] = useState(false);

  const handleAddFilter = () => {
    if (newFilter.value.trim()) {
      addFilter(newFilter);
      setNewFilter({ field: 'node', operator: '=', value: '' });
    }
  };

  const handleSavePreset = () => {
    if (presetName.trim() && filters.length > 0) {
      savePreset(presetName);
      setPresetName('');
    }
  };

  const handleCopyShareLink = () => {
    const queryString = getFilterQueryString();
    const shareUrl = `${window.location.origin}${window.location.pathname}${queryString}`;
    navigator.clipboard.writeText(shareUrl);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const { suggestions, isOpen, handleInputChange } = useFilterAutocomplete(
    newFilter.field,
    catalogLabels,
  );

  return (
    <div class={styles.panel}>
      <div class={styles.section}>
        <h3>Add Filter</h3>
        <div class={styles.filterBuilder}>
          <select
            value={newFilter.field}
            onChange={(e) =>
              setNewFilter({ ...newFilter, field: e.currentTarget.value as any })
            }
            class={styles.select}
          >
            <option value="node">Node</option>
            <option value="status">Status</option>
            <option value="namespace">Namespace</option>
            <option value="label">Label</option>
          </select>

          <select
            value={newFilter.operator}
            onChange={(e) =>
              setNewFilter({ ...newFilter, operator: e.currentTarget.value as any })
            }
            class={styles.select}
          >
            <option value="=">=</option>
            <option value="!=">!=</option>
            <option value="contains">contains</option>
            <option value=">">{'>'}</option>
            <option value="<">{'<'}</option>
          </select>

          <div class={styles.inputWrapper}>
            <input
              type="text"
              placeholder="Filter value..."
              value={newFilter.value}
              onInput={(e) => {
                const value = e.currentTarget.value;
                setNewFilter({ ...newFilter, value });
                handleInputChange(value);
              }}
              class={styles.input}
            />
            {isOpen && suggestions.length > 0 && (
              <ul class={styles.suggestions}>
                {suggestions.map((suggestion) => (
                  <li
                    key={suggestion}
                    onClick={() => setNewFilter({ ...newFilter, value: suggestion })}
                  >
                    {suggestion}
                  </li>
                ))}
              </ul>
            )}
          </div>

          <button onClick={handleAddFilter} class={styles.addButton}>
            + Add
          </button>
        </div>
      </div>

      {filters.length > 0 && (
        <div class={styles.section}>
          <div class={styles.filtersHeader}>
            <h3>Active Filters ({filters.length})</h3>
            <button onClick={clearAllFilters} class={styles.clearButton}>
              Clear All
            </button>
          </div>
          <div class={styles.filtersList}>
            {filters.map((f, idx) => (
              <div key={idx} class={styles.filterTag}>
                <span class={styles.filterText}>
                  {f.field} {f.operator} {f.value}
                </span>
                <button
                  onClick={() => removeFilter(idx)}
                  class={styles.removeButton}
                  aria-label="Remove filter"
                >
                  ✕
                </button>
              </div>
            ))}
          </div>
        </div>
      )}

      <div class={styles.section}>
        <h3>Presets ({presets.length}/{5})</h3>
        {presets.length > 0 && (
          <div class={styles.presetsList}>
            {presets.map((preset) => (
              <div key={preset.name} class={styles.presetItem}>
                <button
                  onClick={() => loadPreset(preset.name)}
                  class={styles.loadButton}
                >
                  📌 {preset.name}
                </button>
                <button
                  onClick={() => deletePreset(preset.name)}
                  class={styles.deleteButton}
                  aria-label="Delete preset"
                >
                  ✕
                </button>
              </div>
            ))}
          </div>
        )}
        <div class={styles.savePreset}>
          <input
            type="text"
            placeholder="Preset name..."
            value={presetName}
            onInput={(e) => setPresetName(e.currentTarget.value)}
            class={styles.input}
          />
          <button
            onClick={handleSavePreset}
            disabled={!presetName.trim() || filters.length === 0}
            class={styles.addButton}
          >
            💾 Save
          </button>
        </div>
      </div>

      {filters.length > 0 && (
        <div class={styles.section}>
          <button onClick={handleCopyShareLink} class={styles.shareButton}>
            {copied ? '✓ Copied!' : '🔗 Share Link'}
          </button>
        </div>
      )}
    </div>
  );
}
