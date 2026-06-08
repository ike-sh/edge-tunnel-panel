import { useEffect, useMemo, useState } from 'react';
import { useSearchParams } from 'react-router-dom';

const STORAGE_KEY = 'etp-h5-layout';

export function useH5Layout() {
  const [searchParams] = useSearchParams();
  const h5Param = searchParams.get('h5');
  const [narrow, setNarrow] = useState(() => (
    typeof window !== 'undefined' && window.matchMedia('(max-width: 768px)').matches
  ));

  useEffect(() => {
    const mq = window.matchMedia('(max-width: 768px)');
    const onChange = () => setNarrow(mq.matches);
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, []);

  useEffect(() => {
    if (h5Param === 'true' || h5Param === '1') {
      localStorage.setItem(STORAGE_KEY, 'true');
    } else if (h5Param === 'false' || h5Param === '0') {
      localStorage.setItem(STORAGE_KEY, 'false');
    }
  }, [h5Param]);

  return useMemo(() => {
    if (h5Param === 'true' || h5Param === '1') return true;
    if (h5Param === 'false' || h5Param === '0') return false;
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored === 'true') return true;
    if (stored === 'false') return false;
    return narrow;
  }, [h5Param, narrow]);
}
