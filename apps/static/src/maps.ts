import axios from 'axios'

const GOOGLE_API_KEY = '[REDACTED_GOOGLE_API_KEY]'

type GoogleGeocodingResponse = {
  results: { geometry: { location: { lat: number; lng: number } } }[],
  status: 'OK' | 'ZERO_RESULTS' | 'OVER_DAILY_LIMIT' | 'OVER_QUERY_LIMIT' | 'REQUEST_DENIED' | 'UNKNOWN_ERROR' | 'INVALID_REQUEST',
  error_message?: string
}

export const configureMapsPage = () => {
  const form = document.querySelector('form')!;
  const addressInput = document.getElementById('address') as HTMLInputElement;
  const searchAddressHandler = async (event: Event) => {
    event.preventDefault();
    const { value: enteredAddress } = addressInput;
    try {
      const response = await axios
        .get<GoogleGeocodingResponse>(
          `https://maps.googleapis.com/maps/api/geocode/json?address=${encodeURI(enteredAddress)}&key=${GOOGLE_API_KEY}`
        )

      if (response.data.status !== 'OK') {
        throw Error('Could not fetch location');
      }
      console.log('Response', response)
      const { Map } = await google.maps.importLibrary('maps') as google.maps.MapsLibrary;
      const { AdvancedMarkerElement } = await google.maps.importLibrary('marker') as google.maps.MarkerLibrary;
    
      const coordinates = response.data.results[0].geometry.location;
      const map = new Map(document.getElementById('map') as HTMLElement, {
        center: coordinates,
        zoom: 8,
        mapId: '803fc7d7903d06da'
      });
      new AdvancedMarkerElement({ position: coordinates, map });

    } catch (error) {
      if (axios.isAxiosError<GoogleGeocodingResponse, Record<string, unknown>>(error)) {
        console.log('ERROR', error.response?.data);
      } else {
        console.error(error);
      }
    }
  }
  form?.addEventListener('submit', searchAddressHandler);
}