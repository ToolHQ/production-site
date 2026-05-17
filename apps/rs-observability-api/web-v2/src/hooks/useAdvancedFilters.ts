import { useEffect, useState, useRef } from 'preact/hooks';

export interface FilterValue {
  field: 'node' | 'status' | 'namespace' | 'label';
  operator: '=' | '!=' | '>' | '<' | 'contains';
  value: string;
}

export interface FilterPreset {
  name: string;
  filters: FilterValue[];
}

const MAX_PRESETS = 5;

export function useAdvancedFilters() {
  const [filters, setFilters] = useState<FilterValue[]>(() => {
    const saved = localStorage.getItem('active-filters');
    return saved ? JSON.parse(saved) : [];
  });

  const [presets, setPresets] = useState<FilterPreset[]>(() => {
    const saved = localStorage.getItem('filter-presets');
    return saved ? JSON.parse(saved) : [];
  });

  // Persist filters
  useEffect(() => {
    localStorage.setItem('active-filters', JSON.stringify(filters));
  }, [filters]);

  // Persist presets
  useEffect(() => {
    localStorage.setItem('filter-presets', JSON.stringify(presets));
  }, [presets]);

  const addFilter = (filter: FilterValue) => {
    setFilters([...filters, { ...filter }]);
  };

  const removeFilter = (index: number) => {
    setFilters(filters.filter((_, i) => i !== index));
  };

  const updateFilter = (index: number, filter: FilterValue) => {
    const newFilters = [...filters];
    newFilters[index] = filter;
    setFilters(newFilters);
  };

  const clearAllFilters = () => {
    setFilters([]);
  };

  // Presets management
  const savePreset = (name: string) => {
    if (presets.length >= MAX_PRESETS) {
      alert(`Maximum ${MAX_PRESETS} presets allowed`);
      return;
    }
    const newPreset: FilterPreset = { name, filters: [...filters] };
    setPresets([...presets, newPreset]);
  };

  const loadPreset = (name: string) => {
    const preset = presets.find((p) => p.name === name);
    if (preset) {
      setFilters([...preset.filters]);
    }
  };

  const deletePreset = (name: string) => {
    setPresets(presets.filter((p) => p.name !== name));
  };

  // Filter evaluation (for frontend filtering)
  const matchesFilters = (item: Record<string, any>): boolean => {
    if (filters.length === 0) return true;

    return filters.every((filter) => {
      const itemValue = item[filter.field];
      const filterValue = filter.value.toLowerCase();

      switch (filter.operator) {
        case '=':
          return String(itemValue).toLowerCase() === filterValue;
        case '!=':
          return String(itemValue).toLowerCase() !== filterValue;
        case 'contains':
          return String(itemValue).toLowerCase().includes(filterValue);
        case '>':
          return Number(itemValue) > Number(filterValue);
        case '<':
          return Number(itemValue) < Number(filterValue);
        default:
          return true;
      }
    });
  };

  // Generate URL query string for sharing
  const getFilterQueryString = (): string => {
    if (filters.length === 0) return '';
    const encoded = btoa(JSON.stringify(filters));
    return `?filters=${encoded}`;
  };

  // Load filters from URL query
  const loadFromQueryString = (queryString: string) => {
    try {
      const match = queryString.match(/\?filters=([^&]+)/);
      if (match) {
        const decoded = JSON.parse(atob(match[1]));
        setFilters(decoded);
      }
    } catch (e) {
      console.error('Failed to parse filter query:', e);
    }
  };

  return {
    filters,
    presets,
    addFilter,
    removeFilter,
    updateFilter,
    clearAllFilters,
    savePreset,
    loadPreset,
    deletePreset,
    matchesFilters,
    getFilterQueryString,
    loadFromQueryString,
  };
}

// Autocomplete for filter values
export function useFilterAutocomplete(field: string, catalogLabels: Record<string, string[]>) {
  const [suggestions, setSuggestions] = useState<string[]>([]);
  const [isOpen, setIsOpen] = useState(false);
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const fetchSuggestions = (query: string) => {
    if (timeoutRef.current) clearTimeout(timeoutRef.current);

    timeoutRef.current = setTimeout(() => {
      const fieldLabels = catalogLabels[field] || [];
      const filtered = fieldLabels.filter((label) =>
        label.toLowerCase().includes(query.toLowerCase()),
      );
      setSuggestions(filtered.slice(0, 10)); // Max 10 suggestions
    }, 150);
  };

  const handleInputChange = (value: string) => {
    if (value.length > 0) {
      fetchSuggestions(value);
      setIsOpen(true);
    } else {
      setSuggestions([]);
      setIsOpen(false);
    }
  };

  return {
    suggestions,
    isOpen,
    setIsOpen,
    handleInputChange,
  };
}
