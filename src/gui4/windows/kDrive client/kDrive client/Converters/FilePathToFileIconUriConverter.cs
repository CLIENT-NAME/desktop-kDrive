/*
 * Infomaniak kDrive - Desktop
 * Copyright (C) 2023-2026 Infomaniak Network SA
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Data;
using System;

namespace Infomaniak.kDrive.Converters
{
    /// <summary>
    /// Converts a file path to the corresponding themed SVG icon URI.
    /// Resolves the resource key from the current theme's resource dictionary.
    /// </summary>
    public class FilePathToFileIconUriConverter : IValueConverter
    {
        private static readonly FilePathToIconResourceKeyConverter _keyConverter = new();

        public object Convert(object value, Type targetType, object parameter, string language)
        {
            // Get the resource key (e.g. "Infomaniak.DS.Icons.Documents.file-pdf")
            var resourceKey = _keyConverter.Convert(value, targetType, parameter, language) as string;
            if (string.IsNullOrEmpty(resourceKey))
                return "";

            // Resolve the URI string from themed resources
            if (Application.Current.Resources.TryGetValue(resourceKey, out var uriString) && uriString is string uri)
                return new Uri(uri);

            return "";
        }

        public object ConvertBack(object value, Type targetType, object parameter, string language)
            => throw new NotImplementedException();
    }
}